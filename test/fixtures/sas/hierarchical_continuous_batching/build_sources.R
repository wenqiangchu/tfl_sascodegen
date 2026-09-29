arguments <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- if (length(arguments) == 1L) sub("^--file=", "", arguments) else
  "test/fixtures/sas/hierarchical_continuous_batching/build_sources.R"
fixture_directory <- normalizePath(dirname(script_path), mustWork = TRUE)
root <- normalizePath(file.path(fixture_directory, "..", "..", "..", ".."), mustWork = TRUE)
source_files <- c(
  "core/errors.R", "chunks/registry.R", "metadata/model.R", "metadata/yaml_codec.R",
  "metadata/workspace.R", "generator/source_generator.R", "generator/report_source.R",
  "emitters/source_input.R", "emitters/continuous.R", "emitters/categorical.R",
  "emitters/hierarchical.R", "emitters/precision.R", "emitters/result_render.R"
)
invisible(lapply(file.path(root, "src", source_files), source, local = FALSE))

batching_fixture <- function(case_name, unit) {
  blocks <- lapply(seq_len(if (case_name == "four") 4L else 2L), function(index) {
    statistics <- lapply(c("n", "mean", "sd", "median", "q1", "q3", "min", "max"), function(id) {
      if (id == "n") list(id = id) else list(id = id, digits = if (index == 1L) 1L else "+1")
    })
    block <- list(
      id = paste0("analysis_", index), anchor_level = "group",
      placement = if (index == 1L) "same_row" else "below",
      type = "continuous_summary", counting_unit = unit,
      analysis_variable = paste0("VALUE", index),
      rows = list(list(id = "row", type = "analysis", label = paste0("Value ", index),
                       statistics = statistics,
                       cell_format = "{n} {mean} {sd} {median} {q1} {q3} {min} {max}"))
    )
    if (unit == "distinct_key") block$distinct_key <- c("USUBJID", "AVISITN")
    if (case_name == "negative") {
      block$rows[[1L]]$statistics <- list(
        list(id = "n"), list(id = "mean", digits = "-9"), list(id = "max", digits = 1L)
      )
      block$rows[[1L]]$cell_format <- "{n} | {mean} | {max}"
    }
    if (case_name == "varied" && index == 2L) {
      block$rows[[1L]]$statistics <- rev(block$rows[[1L]]$statistics)
      block$rows[[1L]]$cell_format <- "{max} {min} {q3} {q1} {median} {sd} {mean} {n}"
      block$rows <- c(
        list(list(id = "heading", type = "label", label = paste(rep("Details", 60L), collapse = " "))),
        block$rows,
        list(list(id = "count", type = "analysis", label = "Count",
                  statistics = list(list(id = "n")), cell_format = "{n}"))
      )
    }
    block
  })
  columns <- lapply(1:3, function(index) list(
    id = c("overall", "subset", "empty")[[index]],
    label = c("Overall", "Subset", "Empty")[[index]],
    condition = c("1", "USUBJID in ('01', '02')", "0")[[index]],
    display_order = index, width = 1, alignment = "center"
  ))
  new_metadata_bundle(
    populations = list(list(id = "population", label = "Population", expression = "1")),
    headers = list(list(id = "header", source_data = "work.hb_adsl",
                        orientation = "landscape", columns = columns)),
    tables = list(list(id = paste0("hb_", case_name), population_id = "population",
                       header_id = "header", template_id = "template")),
    templates = list(list(id = "template", body = list(stub_header = "Group", chunks = list(list(
      id = "hierarchy", type = "hierarchical_summary", source_data = paste0("work.hb_", case_name),
      source_contract = list(grain = "observation", subject_key = "USUBJID",
                             record_key = c("USUBJID", "RECORD_ID"), duplicate_policy = "error"),
      levels = list(list(
        id = "group", variable = "GROUP_VALUE", order_variable = "GROUP_ORDER",
        order_direction = "asc", node_role = "analysis", node_analysis_id = "analysis_1",
        missing_policy = "exclude",
        result_sort = list(metric = list(analysis_id = "analysis_2", row_id = "row", statistic_id = "mean"),
                           column_order = c(1L, 0L), direction = "desc")
      )), analysis_blocks = blocks
    )))))
  )
}

# An alternate registered emitter exercises the independent procedure path
# without introducing a production option solely for test comparisons.
independent_registry <- default_chunk_registry()
independent_registry$definitions$continuous_summary$emitter <- function(plan, resolved) {
  continuous_summary_emitter(plan, resolved)
}
cases <- c(record = "record", four = "record", varied = "record", negative = "record",
           subject = "distinct_subject", key = "distinct_key",
           empty = "record", missing = "distinct_subject",
           subject_conflict = "distinct_subject", key_conflict = "distinct_key")
generated <- file.path(fixture_directory, "generated")
dir.create(generated, recursive = TRUE, showWarnings = FALSE)
for (case_name in names(cases)) {
  bundle <- batching_fixture(case_name, cases[[case_name]])
  for (mode in c("shared", "independent")) {
    registry <- if (mode == "shared") default_chunk_registry() else independent_registry
    result <- generate_table_source(bundle, bundle$tables[[1L]]$id, registry = registry,
                                    include_duplicate_check = FALSE)
    if (!isTRUE(result$passed)) stop("Could not generate batching fixture: ", case_name)
    count <- lengths(regmatches(result$source, gregexpr("proc means", result$source, fixed = TRUE)))
    stopifnot(count == if (mode == "shared") 1L else
      length(bundle$templates[[1L]]$body$chunks[[1L]]$analysis_blocks))
    writeLines(result$source, file.path(generated, paste0(case_name, "_", mode, ".sas")), useBytes = TRUE)
  }
}
message("Generated paired shared/independent programs in: ", generated)
