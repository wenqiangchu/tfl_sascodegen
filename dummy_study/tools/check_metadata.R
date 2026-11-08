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

# The bundle loader owns the reading and parsing; this tool adds the generator so
# it can also produce the SAS source. See dummy_study/tools/load_bundle.R.
source(file.path("dummy_study", "tools", "load_bundle.R"))
source_bundle_runtime(".")
invisible(lapply(file.path("src", c("generator/source_generator.R",
                                    "generator/report_source.R")), source, local = FALSE))

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

loaded <- tryCatch(load_dummy_workspace("."),
                  error = function(error) fail(conditionMessage(error)))
manifest <- loaded$manifest
bundle <- loaded$value

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
