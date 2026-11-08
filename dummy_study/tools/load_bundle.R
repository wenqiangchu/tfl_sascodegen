#!/usr/bin/env Rscript
# Load the dummy study bundle for a verification script or a test.
#
# One place sources the production codec, reads the authored YAML, and parses it
# through the production model, so the three consumers cannot drift apart:
# dummy_study/tools/check_metadata.R, dummy_study/verify/compare_with_sas.R and
# test/testthat/test-dummy-study-metadata.R.
#
# Two properties matter, because this used to be duplicated three times:
#   - the full source list is sourced, including core/errors.R. The codec's failure
#     path calls new_error_item(), so sourcing only model.R and yaml_codec.R made a
#     malformed bundle crash with "could not find function" instead of reporting it.
#   - parsing goes through parse_bundle_value(), so defaults and type normalisation
#     are applied and any structural error is reported. Reading the raw YAML and
#     taking $value discarded exactly the errors this is meant to surface.
#
# Nothing here is specific to a table or a run: it returns the parsed workspace and
# the raw bundle, and the caller decides what to do next.

# Every production file the metadata path needs. Pagination and the emitters are
# not required to parse a bundle, so they are left out; check_metadata.R adds the
# generator files it needs on top of this list.
# The chunk registry validates chunk types during parsing, so the emitter files
# that register them are part of the metadata path even though nothing is emitted.
bundle_source_files <- function() {
  c("core/errors.R", "chunks/registry.R", "metadata/model.R",
    "metadata/yaml_codec.R", "metadata/workspace.R",
    "emitters/source_input.R", "emitters/continuous.R", "emitters/categorical.R",
    "emitters/hierarchical.R", "emitters/precision.R", "emitters/result_render.R")
}

source_bundle_runtime <- function(root = ".") {
  paths <- file.path(root, "src", bundle_source_files())
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0L) {
    stop("Missing production source file(s): ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  for (path in paths) source(path, local = FALSE)
  invisible(paths)
}

format_bundle_error <- function(error) {
  path <- if (!is.null(error$path)) paste0(error$path, ": ") else ""
  paste0(path, error$message)
}

# Read the authored YAML into the raw bundle value. Each entry is parsed for YAML
# syntax only; structural validation happens once, on the whole bundle, so the
# error list is complete rather than first-failure.
read_bundle_entries <- function(root = ".") {
  metadata_dir <- file.path(root, "dummy_study", "metadata")
  read_entry <- function(path) {
    text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    parsed <- parse_yaml_document_text(text)
    if (length(parsed$errors) > 0L) {
      stop(sprintf("YAML parse failed for %s:\n%s", path,
                   paste(vapply(parsed$errors, format_bundle_error, ""),
                         collapse = "\n")), call. = FALSE)
    }
    parsed$value
  }
  entry_files <- function(directory) {
    paths <- list.files(file.path(metadata_dir, directory), pattern = "[.]yaml$",
                        full.names = TRUE)
    if (length(paths) == 0L) {
      stop("No YAML files found under ", directory, call. = FALSE)
    }
    sort(paths)
  }
  list(
    manifest = read_entry(file.path(metadata_dir, "manifest.yaml")),
    populations = read_entry(file.path(metadata_dir, "populations.yaml")),
    headers = read_entry(file.path(metadata_dir, "headers.yaml")),
    tables = unname(lapply(entry_files("tables"), read_entry)),
    templates = unname(lapply(entry_files("templates"), read_entry))
  )
}

build_bundle_value <- function(entries) {
  new_metadata_bundle(
    populations = entries$populations$populations,
    headers = entries$headers$headers,
    tables = entries$tables,
    templates = entries$templates
  )
}

# Parse and validate. Returns both representations: `value` is what the codec and
# the generator consume, `raw` is the authored structure for callers that still
# need bundle-level lookup (compare_with_sas.R resolves headers itself).
load_dummy_workspace <- function(root = ".") {
  source_bundle_runtime(root)
  entries <- read_bundle_entries(root)
  schema <- entries$manifest$schema_version
  if (is.null(schema) || !identical(as.integer(schema), 2L)) {
    stop("Unsupported manifest schema_version: ",
         paste(format(schema), collapse = ","), " (expected 2)", call. = FALSE)
  }
  bundle <- build_bundle_value(entries)
  parsed <- parse_bundle_value(bundle)
  if (length(parsed$errors) > 0L) {
    stop(sprintf("%d bundle error(s):\n%s", length(parsed$errors),
                 paste(vapply(parsed$errors, format_bundle_error, ""),
                       collapse = "\n")), call. = FALSE)
  }
  list(value = parsed$value,
       workspace = new_metadata_workspace(bundle),
       raw_bundle = bundle,
       manifest = entries$manifest)
}
