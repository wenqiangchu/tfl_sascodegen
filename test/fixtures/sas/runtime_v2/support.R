# Shared setup for external runtime fixtures; this file never starts SAS.
runtime_source_files <- c(
  "core/errors.R", "chunks/registry.R", "metadata/model.R", "metadata/yaml_codec.R",
  "metadata/workspace.R", "generator/source_generator.R", "generator/report_source.R",
  "emitters/source_input.R", "emitters/continuous.R", "emitters/categorical.R",
  "emitters/hierarchical.R", "emitters/result_render.R"
)
invisible(lapply(file.path("src", runtime_source_files), source, local = FALSE))

runtime_write <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), path)
}

runtime_require <- function(result) {
  if (!isTRUE(result$passed)) {
    stop(paste(vapply(result$errors, function(error) error$message, ""), collapse = "\n"))
  }
  result
}
