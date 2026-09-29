# Load the same generator and fixture definitions used by the correctness cases.
source("test/fixtures/sas/hierarchical_row_assembly/build_sources.R")
independent_registry <- default_chunk_registry()
independent_registry$definitions$continuous_summary$emitter <- function(plan, resolved) {
  continuous_summary_emitter(plan, resolved)
}
for (block_count in c(2L, 4L)) {
  bundle <- row_assembly_fixture()
  bundle$headers[[1L]]$columns[[2L]]$condition <- "mod(input(USUBJID,12.),2)=0"
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  if (block_count == 4L) {
    for (index in 3:4) {
      block <- chunk$analysis_blocks[[2L]]
      block$id <- paste0("below", index)
      block$analysis_variable <- paste0("VALUE", index)
      chunk$analysis_blocks[[index]] <- block
    }
  }
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
  for (mode in c("shared", "independent")) {
    registry <- if (mode == "shared") default_chunk_registry() else independent_registry
    result <- generate_table_source(bundle, "ra", registry = registry, include_duplicate_check = FALSE)
    stopifnot(result$passed)
    position <- regexpr("/* Write the RTF in the caller's current SAS working directory. */",
                       result$source, fixed = TRUE)[[1L]]
    stopifnot(position > 0L)
    source_path <- file.path(generated, paste0("benchmark_", block_count, "_", mode, ".sas"))
    writeLines(substr(result$source, 1L, position - 1L), source_path, useBytes = TRUE)
    source_lines <- readLines(source_path, warn = FALSE)
    message(sprintf("Source size: blocks=%d mode=%s lines=%d data_steps=%d procedures=%d",
      block_count, mode, length(source_lines),
      sum(grepl("^data ", source_lines)), sum(grepl("^proc ", source_lines))))
  }
}
