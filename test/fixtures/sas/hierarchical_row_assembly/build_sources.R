arguments <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- if (length(arguments) == 1L) sub("^--file=", "", arguments) else
  "test/fixtures/sas/hierarchical_row_assembly/build_sources.R"
fixture_directory <- normalizePath(dirname(script_path), mustWork = TRUE)
root <- normalizePath(file.path(fixture_directory, "..", "..", "..", ".."), mustWork = TRUE)
source_files <- c(
  "core/errors.R", "chunks/registry.R", "metadata/model.R", "metadata/yaml_codec.R",
  "metadata/workspace.R", "generator/source_generator.R", "generator/report_source.R",
  "emitters/source_input.R", "emitters/continuous.R", "emitters/categorical.R",
  "emitters/hierarchical.R", "emitters/precision.R", "emitters/result_render.R"
)
invisible(lapply(file.path(root, "src", source_files), source, local = FALSE))
source(file.path(fixture_directory, "metadata.R"))

generated <- file.path(fixture_directory, "generated")
dir.create(generated, recursive = TRUE, showWarnings = FALSE)
for (case in c("basic", "sorted", "multilevel", "mixed", "empty")) {
  bundle <- row_assembly_fixture(case)
  stopifnot(length(parse_bundle_value(bundle)$errors) == 0L)
  result <- generate_table_source(bundle, "ra")
  stopifnot(isTRUE(result$passed))
  # Exercise unchanged generation up to final assembly, without writing a report.
  marker <- "/* Write the RTF in the caller's current SAS working directory. */"
  position <- regexpr(marker, result$source, fixed = TRUE)[[1L]]
  stopifnot(position > 0L)
  writeLines(substr(result$source, 1L, position - 1L),
             file.path(generated, paste0(case, ".sas")), useBytes = TRUE)

  rows <- row_assembly_expected(case)
  statements <- unlist(lapply(seq_len(nrow(rows)), function(index) {
    row <- rows[index, , drop = FALSE]
    c(vapply(names(row), function(field) {
      value <- row[[field]]
      literal <- if (is.character(value)) sas_character_literal(value) else as.character(value)
      paste0("  ", field, " = ", literal, ";")
    }, ""), "  output;")
  }), use.names = FALSE)
  writeLines(c(
    "/* Hand-calculated expectations; never derived from generated results. */",
    "data work.ra_expected;",
    "  length chunk_id row_id $&_TFL_ID_LEN runtime_row_id $&_TFL_RUNTIME_LEN;",
    "  length node_key $&_TFL_NODE_LEN row_role $16 label $&_TFL_LABEL_LEN;",
    "  length col_001 col_002 col_003 $&_TFL_CELL_LEN;",
    "  length chunk_order row_sequence indent_level hierarchy_level 8;",
    statements, "  stop;", "run;"
  ), file.path(generated, paste0(case, "_expected.sas")), useBytes = TRUE)
}
message("Generated row-assembly programs and independent expectations in: ", generated)
