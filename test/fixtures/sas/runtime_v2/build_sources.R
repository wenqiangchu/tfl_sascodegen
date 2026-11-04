source("test/fixtures/sas/runtime_v2/support.R")
source("test/fixtures/sas/runtime_v2/format_cases.R")
destination <- "study/validation_v2/synthetic"
for (case in c("basic", "empty", "empty_label", "empty_error", "missing_label", "missing_error", "sorted", "third_level",
               "reversed", "duplicated", "same_variable", "long_labels", "unformatted_order")) {
  fixture <- format_case(case)
  source <- runtime_require(generate_table_source(fixture$bundle, fixture$bundle$tables[[1L]]$id,
                                                  include_duplicate_check = FALSE))$source
  runtime_write(source, file.path(destination, case, "program.sas"))
  writeBin(canonical_archive_bytes(fixture$bundle)$bytes, file.path(destination, case, "metadata.zip"))
  fixture$bundle <- NULL
  jsonlite::write_json(fixture, file.path(destination, case, "expected.json"),
                      auto_unbox = TRUE, pretty = TRUE)
}
cat("Built synthetic format runtime cases.\n")
