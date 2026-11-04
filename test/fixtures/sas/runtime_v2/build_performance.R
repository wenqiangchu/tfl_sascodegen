# Run from an isolated source checkout; arguments are output directory and rows.
source("test/fixtures/sas/runtime_v2/support.R")
source("test/fixtures/sas/runtime_v2/format_cases.R")
args <- commandArgs(trailingOnly = TRUE)
destination <- args[[1L]]
records <- as.integer(args[[2L]])
bundle <- format_case("basic")$bundle
bundle$tables[[1L]]$id <- "rv_performance"
bundle$tables[[1L]]$custom_code$before <- paste(c(
  "data rv_adsl; length USUBJID $3; do subject=1 to 60; USUBJID=put(subject,z3.); output; end; run;",
  paste0("proc format; value rvbench ", paste(sprintf("%d='Category %02d'", 1:20, 1:20), collapse = " "), "; run;"),
  "data rv_events; length USUBJID $3;",
  paste0("  do seq=1 to ", records, "; USUBJID=put(mod(seq-1,60)+1,z3.); VISIT=mod(seq-1,19)+1; output; end; run;"),
  "%let rv_analysis_start=%sysfunc(datetime());"
), collapse = "\n")
bundle$tables[[1L]]$custom_code$after <- paste(c(
  "%let rv_analysis_seconds=%sysevalf(%sysfunc(datetime())-&rv_analysis_start);",
  "%put NOTE: [PERFORMANCE] analysis_seconds=&rv_analysis_seconds;"
), collapse = "\n")
bundle$headers[[1L]]$columns <- bundle$headers[[1L]]$columns[1L]
chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
chunk$levels <- chunk$levels[1L]
chunk$levels[[1L]]$format <- "rvbench"
chunk$analysis_blocks <- chunk$analysis_blocks[1L]
bundle$templates[[1L]]$body$chunks <- list(chunk)
program <- runtime_require(generate_table_source(bundle, "rv_performance", include_duplicate_check = FALSE))$source
# Measure analysis through assembly, excluding RTF rendering and snapshot I/O.
program <- strsplit(program, "/* Write the RTF", fixed = TRUE)[[1L]][[1L]]
runtime_write(program, file.path(destination, "program.sas"))
