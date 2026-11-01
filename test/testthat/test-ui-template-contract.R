template_sort_fixture <- function() {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(
      id = "h", source_data = "work.population", orientation = "landscape",
      columns = list(list(id = "all", label = "All", condition = "1",
                          display_order = 1L, width = 1, alignment = "center"))
    )),
    tables = list(list(id = "t", population_id = "p", header_id = "h",
                       template_id = "tpl")),
    templates = list(list(id = "tpl", body = list(
      stub_header = "SOC",
      chunks = list(list(
        id = "c", type = "hierarchical_summary", source_data = "work.events",
        levels = list(list(
          id = "l", variable = "SOC", format = "visit_fmt", order_variable = "SOC",
          order_direction = "asc", node_role = "label", missing_policy = "exclude",
          result_sort = list(
            metric = list(analysis_id = "a", row_id = "r", statistic_id = "n"),
            column_order = c(1L, 0L), direction = "desc"
          )
        )),
        analysis_blocks = list(list(
          id = "a", anchor_level = "l", placement = "below",
          type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
          denominator = list(scope = "chunk_source", unit = "distinct_key",
                             expression = "DENFL = 'Y'", distinct_key = c("USUBJID", "CYCLE")),
          rows = list(list(id = "r", type = "analysis", label = "Subjects",
                           condition = "1", statistics = list(list(id = "n")),
                           cell_format = "{n}"))
        ))
      ))
    )))
  )
}

template_contract_ui_environment <- function() {
  ui_environment <- new.env(parent = globalenv())
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(shinydashboard))
  suppressPackageStartupMessages(library(DT))
  ui_files <- list.files(file.path(project_root, "src", "ui"),
                         pattern = "[.]R$", full.names = TRUE)
  invisible(lapply(ui_files, source, local = ui_environment))
  ui_environment
}

testthat::test_that("template collection and save preserve imported result sorting", {
  ui_environment <- template_contract_ui_environment()
  fixture <- template_sort_fixture()
  decorated <- ui_environment$decorate_template_ui_ids(fixture$templates[[1L]])

  shiny::testServer(ui_environment$metadata_editor_server_impl, {
    workspace(new_metadata_workspace(fixture))
    metadata_loaded(TRUE)
    active_editor(list(document_type = "template", document_id = "tpl"))
    active_draft(list(operation = "update", original = fixture$templates[[1L]]))
    template_value(decorated)
    session$setInputs(template_stub_header = "Updated SOC")

    collected <- collect_template_from_ui(strip_ids = TRUE)
    expected <- fixture$templates[[1L]]$body$chunks[[1L]]$levels[[1L]]$result_sort
    expected_denominator <- fixture$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]]$denominator
    testthat::expect_identical(collected$body$chunks[[1L]]$analysis_blocks[[1L]]$denominator,
                               expected_denominator)
    testthat::expect_identical(collected$body$chunks[[1L]]$levels[[1L]]$format,
                               "visit_fmt")
    testthat::expect_identical(collected$body$chunks[[1L]]$levels[[1L]]$result_sort,
                               expected)

    save_active("template")
    saved <- workspace_saved_snapshot(workspace())$templates[[1L]]
    chunk <- saved$body$chunks[[1L]]
    sort <- chunk$levels[[1L]]$result_sort
    testthat::expect_identical(chunk$analysis_blocks[[1L]]$denominator, expected_denominator)
    testthat::expect_identical(saved$body$stub_header, "Updated SOC")
    testthat::expect_false(is.null(sort))
    testthat::expect_identical(sort$metric$analysis_id, chunk$analysis_blocks[[1L]]$id)
    testthat::expect_identical(sort$metric$row_id, chunk$analysis_blocks[[1L]]$rows[[1L]]$id)
    testthat::expect_identical(sort$column_order, c(1L, 0L))
    testthat::expect_identical(sort$direction, "desc")
  })
})

testthat::test_that("primitive and nested denominator edits survive save and bundle export", {
  ui_environment <- template_contract_ui_environment()
  cases <- list(
    list(nested = TRUE, denominator = list(
      scope = "current_group", unit = "distinct_key", expression = "EVALFL = 'Y'",
      distinct_key = c("USUBJID", "VISITNUM"))),
    list(nested = TRUE, denominator = list(scope = "header_population", unit = "distinct_subject")),
    list(nested = FALSE, denominator = list(
      scope = "header_population", unit = "distinct_subject", expression = "EVALFL = 'Y'")),
    list(nested = FALSE, denominator = list(
      scope = "chunk_source", unit = "distinct_key", expression = "EVALFL = 'Y'",
      distinct_key = c("USUBJID", "AESEQ")))
  )
  for (case in cases) {
    fixture <- template_sort_fixture()
    chunk <- fixture$templates[[1L]]$body$chunks[[1L]]
    if (!case$nested) {
      chunk <- chunk$analysis_blocks[[1L]]
      chunk$anchor_level <- chunk$placement <- NULL
      chunk$source_data <- "work.events"
      fixture$templates[[1L]]$body$chunks[[1L]] <- chunk
    }
    prefix <- if (case$nested) "chunk_1_block_1_" else "chunk_1_"
    controls <- if (case$nested) {
      ui_environment$block_ui(chunk$analysis_blocks[[1L]], "chunk_1_", 1L, chunk)
    } else ui_environment$chunk_card_ui(chunk, 1L)
    expected <- case$denominator
    inputs <- list(expected$scope, expected$unit,
                   paste(expected$distinct_key %||% character(), collapse = ", "),
                   expected$expression %||% "")
    names(inputs) <- paste0(prefix, c("den_scope", "den_unit", "den_distinct_key", "den_expression"))
    for (id in names(inputs)) {
      testthat::expect_match(as.character(controls), paste0('id="', id, '"'), fixed = TRUE)
    }
    extract_denominator <- function(template) {
      value <- template$body$chunks[[1L]]
      if (case$nested) value <- value$analysis_blocks[[1L]]
      value$denominator
    }
    testthat::expect_false(identical(extract_denominator(fixture$templates[[1L]]), expected))
    shiny::testServer(ui_environment$metadata_editor_server_impl, {
      workspace(new_metadata_workspace(fixture))
      metadata_loaded(TRUE)
      active_editor(list(document_type = "template", document_id = "tpl"))
      active_draft(list(operation = "update", original = fixture$templates[[1L]]))
      template_value(ui_environment$decorate_template_ui_ids(fixture$templates[[1L]]))
      do.call(session$setInputs, inputs)
      testthat::expect_identical(extract_denominator(collect_template_from_ui(strip_ids = TRUE)), expected)
      save_active("template")
      saved <- workspace_saved_snapshot(workspace())
      testthat::expect_identical(extract_denominator(saved$templates[[1L]]), expected)
      imported <- parse_bundle_archive(canonical_archive_bytes(saved))
      testthat::expect_true(imported$passed)
      testthat::expect_identical(extract_denominator(imported$workspace$templates[[1L]]), expected)
    })
  }
})
