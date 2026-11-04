source("test/fixtures/sas/runtime_v2/support.R")
source("test/fixtures/sas/runtime_v2/denominator_case.R")
fixture <- denominator_case()
destination <- "study/validation_v2/denominators"
program <- runtime_require(generate_table_source(fixture$bundle, "rv_denominators", include_duplicate_check = FALSE))$source
runtime_write(program, file.path(destination, "program.sas"))
writeBin(canonical_archive_bytes(fixture$bundle)$bytes, file.path(destination, "metadata.zip"))
fixture$bundle <- NULL
jsonlite::write_json(fixture, file.path(destination, "expected.json"), auto_unbox = TRUE, pretty = TRUE)

# Duplicate Header input is outside the analysis contract. Its oracle checks
# diagnostics, continuation and unchanged records, not inflated analysis values.
invalid <- denominator_case()$bundle
invalid$populations[[1L]]$expression <- "USUBJID ne '99'"
invalid$tables[[1L]]$custom_code$before <- paste(invalid$tables[[1L]]$custom_code$before,
  "data work.rv_extra; length USUBJID $2 HQUAL $1; USUBJID='99'; HQUAL='N'; output; output; run;",
  "data work.rv_adsl; set work.rv_adsl work.rv_adsl(where=(USUBJID='01')) work.rv_extra; run;", sep = "\n")
for (checked in c(TRUE, FALSE)) {
  program <- runtime_require(generate_table_source(invalid, "rv_denominators", include_duplicate_check = checked))$source
  runtime_write(program, file.path(destination, if (checked) "header_checked.sas" else "header_unchecked.sas"))
}
