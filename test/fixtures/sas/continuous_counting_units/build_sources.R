command_arguments <- commandArgs(trailingOnly = FALSE)
file_argument <- grep("^--file=", command_arguments, value = TRUE)
script_path <- if (length(file_argument) == 1L) {
  sub("^--file=", "", file_argument)
} else {
  file.path("test", "fixtures", "sas", "continuous_counting_units", "build_sources.R")
}
root <- normalizePath(file.path(dirname(script_path), "..", "..", "..", ".."),
                      mustWork = TRUE)

source_files <- c(
  "src/core/errors.R",
  "src/chunks/registry.R",
  "src/metadata/model.R",
  "src/metadata/yaml_codec.R",
  "src/metadata/workspace.R",
  "src/generator/source_generator.R",
  "src/generator/report_source.R",
  "src/emitters/source_input.R",
  "src/emitters/continuous.R",
  "src/emitters/categorical.R",
  "src/emitters/hierarchical.R",
  "src/emitters/precision.R",
  "src/emitters/result_render.R"
)
invisible(lapply(file.path(root, source_files), source, local = FALSE))

fixture_directory <- file.path(root, "test", "fixtures", "sas", "continuous_counting_units")
generated_directory <- file.path(fixture_directory, "generated")
dir.create(generated_directory, recursive = TRUE, showWarnings = FALSE)

fixture_bundle <- function(table_id, source_data, counting_unit, distinct_key = NULL) {
  block <- list(
    id = "analysis_001",
    anchor_level = "level_001",
    placement = "below",
    type = "continuous_summary",
    counting_unit = counting_unit,
    analysis_variable = "AVAL",
    rows = list(list(
      id = "row_001",
      type = "analysis",
      label = "Analysis value",
      statistics = list(
        list(id = "n"),
        list(id = "mean", digits = 1L),
        list(id = "min", digits = 1L),
        list(id = "max", digits = 1L)
      ),
      cell_format = "{n} {mean} [{min}, {max}]"
    ))
  )
  if (!is.null(distinct_key)) block$distinct_key <- distinct_key

  new_metadata_bundle(
    populations = list(list(id = "population", label = "Population", expression = "1")),
    headers = list(list(
      id = "header",
      source_data = "work.cu_adsl",
      orientation = "landscape",
      columns = list(list(
        id = "overall",
        label = "Overall",
        condition = "1",
        display_order = 1L,
        width = 1,
        alignment = "center"
      ))
    )),
    tables = list(list(
      id = table_id,
      population_id = "population",
      header_id = "header",
      template_id = "template"
    )),
    templates = list(list(
      id = "template",
      body = list(
        stub_header = "Group",
        chunks = list(list(
          id = "hierarchy_001",
          type = "hierarchical_summary",
          source_data = source_data,
          source_contract = list(
            grain = "observation",
            subject_key = "USUBJID",
            record_key = c("USUBJID", "RECORD_ID"),
            duplicate_policy = "error"
          ),
          levels = list(list(
            id = "level_001",
            variable = "GROUP_VALUE",
            order_variable = "GROUP_ORDER",
            order_direction = "asc",
            node_role = "label",
            missing_policy = "exclude"
          )),
          analysis_blocks = list(block)
        ))
      )
    ))
  )
}

cases <- list(
  record = fixture_bundle("cu_record", "work.cu_record", "record"),
  distinct_subject = fixture_bundle(
    "cu_distinct_subject", "work.cu_distinct_subject", "distinct_subject"
  ),
  distinct_key = fixture_bundle(
    "cu_distinct_key", "work.cu_distinct_key", "distinct_key",
    distinct_key = c("USUBJID", "AVISITN")
  ),
  distinct_subject_conflict = fixture_bundle(
    "cu_distinct_subject_conflict", "work.cu_distinct_subject_conflict",
    "distinct_subject"
  )
)

shared_level <- fixture_bundle("cu_shared_level", "work.cu_shared_level", "record")
shared_chunk <- shared_level$templates[[1L]]$body$chunks[[1L]]
shared_chunk$analysis_blocks[[2L]] <- list(
  id = "analysis_002",
  anchor_level = "level_001",
  placement = "below",
  type = "categorical_summary_nonexclusive",
  counting_unit = "distinct_subject",
  denominator = list(scope = "current_group", unit = "distinct_subject"),
  rows = list(list(
    id = "category_row_001",
    type = "analysis",
    label = "Flagged subjects",
    condition = "FLAG = 'Y'",
    statistics = list(list(id = "n"), list(id = "pct", digits = 1L)),
    cell_format = "{n} ({pct}%)"
  ))
)
shared_level$templates[[1L]]$body$chunks[[1L]] <- shared_chunk
cases$shared_level <- shared_level

for (case_name in names(cases)) {
  table_id <- cases[[case_name]]$tables[[1L]]$id
  result <- generate_table_source(cases[[case_name]], table_id, output_mode = "report")
  if (!isTRUE(result$passed)) {
    stop(sprintf("Could not generate SAS fixture '%s'.", case_name), call. = FALSE)
  }
  if (identical(case_name, "shared_level")) {
    merge_count <- lengths(regmatches(
      result$source,
      gregexpr("create table _TFL_HMERGE_001_001 as", result$source, fixed = TRUE)
    ))
    if (!identical(merge_count, 1L)) {
      stop("The shared-level fixture must contain exactly one membership expansion.",
           call. = FALSE)
    }
  }
  writeLines(result$source, file.path(generated_directory, paste0(case_name, ".sas")),
             useBytes = TRUE)
}

message("Generated SAS fixture programs in: ", generated_directory)
