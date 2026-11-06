#!/usr/bin/env Rscript
# Validate and materialise the dummy study metadata bundle.
#
# The metadata under dummy_study/metadata/ is authored as plain YAML so that it
# stays reviewable next to the shells. This tool parses it with the production
# codec, validates it with the production model, round-trips the canonical
# archive, and generates the SAS source for every table. Nothing is written
# unless --write is passed, so the default run is a pure check.
#
# Usage (from the repository root):
#   Rscript dummy_study/tools/check_metadata.R
#   Rscript dummy_study/tools/check_metadata.R --write

args <- commandArgs(trailingOnly = TRUE)
write_output <- "--write" %in% args

runtime_source_files <- c(
  "core/errors.R", "chunks/registry.R", "metadata/model.R", "metadata/yaml_codec.R",
  "metadata/workspace.R", "generator/source_generator.R", "generator/report_source.R",
  "emitters/source_input.R", "emitters/continuous.R", "emitters/categorical.R",
  "emitters/hierarchical.R", "emitters/precision.R", "emitters/result_render.R"
)
invisible(lapply(file.path("src", runtime_source_files), source, local = FALSE))

metadata_dir <- file.path("dummy_study", "metadata")
output_dir <- file.path("dummy_study", "generated")

fail <- function(...) {
  message(paste0(...))
  quit(status = 1L)
}

format_error <- function(error) {
  path <- if (!is.null(error$path)) paste0(error$path, ": ") else ""
  paste0(path, error$message)
}

# Mirrors the fixture helper: a failed generation result carries an errors list.
runtime_require <- function(result) {
  if (!isTRUE(result$passed)) {
    fail(paste(vapply(result$errors, function(error) error$message, ""), collapse = "\n"))
  }
  result
}

read_entry <- function(path) {
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  parsed <- parse_yaml_document_text(text)
  if (length(parsed$errors) > 0L) {
    fail(sprintf("YAML parse failed for %s:\n%s", path,
                 paste(vapply(parsed$errors, format_error, ""), collapse = "\n")))
  }
  parsed$value
}

entry_files <- function(directory) {
  paths <- list.files(file.path(metadata_dir, directory), pattern = "\\.yaml$",
                      full.names = TRUE)
  if (length(paths) == 0L) fail(sprintf("No YAML files found under %s", directory))
  sort(paths)
}

manifest <- read_entry(file.path(metadata_dir, "manifest.yaml"))
populations <- read_entry(file.path(metadata_dir, "populations.yaml"))
headers <- read_entry(file.path(metadata_dir, "headers.yaml"))
table_values <- lapply(entry_files("tables"), read_entry)
template_values <- lapply(entry_files("templates"), read_entry)

bundle <- new_metadata_bundle(
  populations = populations$populations,
  headers = headers$headers,
  tables = unname(table_values),
  templates = unname(template_values)
)
stopifnot(identical(as.integer(manifest$schema_version), 2L))

parsed <- parse_bundle_value(bundle)
if (length(parsed$errors) > 0L) {
  fail(sprintf("%d bundle error(s):\n%s", length(parsed$errors),
               paste(vapply(parsed$errors, format_error, ""), collapse = "\n")))
}
bundle <- parsed$value

archive <- canonical_archive_bytes(bundle)
restored <- runtime_require(parse_bundle_archive(archive))$workspace
round_trip <- canonical_archive_bytes(restored)
if (!identical(archive$bytes, round_trip$bytes)) {
  fail("Canonical archive is not stable across a round trip.")
}

# The generator returns either a line vector or one newline-delimited string.
as_lines <- function(source) {
  if (length(source) == 1L && grepl("
", source, fixed = TRUE)) {
    strsplit(source, "
", fixed = TRUE)[[1L]]
  } else {
    source
  }
}

generated <- list()
for (table in restored$tables) {
  first <- runtime_require(generate_table_source(restored, table$id, output_mode = "report"))
  second <- runtime_require(generate_table_source(restored, table$id, output_mode = "report"))
  if (!identical(first$source, second$source)) {
    fail(sprintf("Generation for '%s' is not deterministic.", table$id))
  }
  generated[[table$id]] <- as_lines(first$source)
}

cat(sprintf("bundle ok: %d populations, %d headers, %d tables, %d templates\n",
            length(restored$populations), length(restored$headers),
            length(restored$tables), length(restored$templates)))
for (id in names(generated)) {
  cat(sprintf("  %-26s %5d source lines\n", id, length(generated[[id]])))
}

if (write_output) {
  runtime_write_text <- function(text, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), path)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  writeBin(archive$bytes, file.path(output_dir, "metadata.zip"))
  for (id in names(generated)) {
    runtime_write_text(generated[[id]], file.path(output_dir, "sas", paste0(id, ".sas")))
  }
  cat(sprintf("wrote %s and %d SAS program(s)\n",
              file.path(output_dir, "metadata.zip"), length(generated)))
}
