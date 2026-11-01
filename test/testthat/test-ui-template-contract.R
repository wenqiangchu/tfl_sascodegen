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
          id = "l", variable = "SOC", order_variable = "SOC",
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

testthat::test_that("template collection and save preserve imported result sorting", {
  ui_environment <- new.env(parent = globalenv())
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(shinydashboard))
  suppressPackageStartupMessages(library(DT))
  ui_files <- list.files(file.path(project_root, "src", "ui"),
                         pattern = "[.]R$", full.names = TRUE)
  invisible(lapply(ui_files, source, local = ui_environment))
  fixture <- template_sort_fixture()
  decorated <- ui_environment$decorate_template_ui_ids(fixture$templates[[1L]])

  shiny::testServer(ui_environment$metadata_editor_server_impl, {
    workspace(new_metadata_workspace(fixture))
    metadata_loaded(TRUE)
    active_editor(list(document_type = "template", document_id = "tpl"))
    active_draft(list(operation = "update", original = fixture$templates[[1L]]))
    template_value(decorated)
    session$setInputs(template_stub_header = "Updated SOC")
    session$setInputs(chunk_1_den_scope = "chunk_source")
    session$setInputs(chunk_1_den_unit = "distinct_key")
    session$setInputs(chunk_1_den_distinct_key = "USUBJID, CYCLE")
    session$setInputs(chunk_1_den_expression = "DENFL = 'Y'")

    collected <- collect_template_from_ui(strip_ids = TRUE)
    expected <- fixture$templates[[1L]]$body$chunks[[1L]]$levels[[1L]]$result_sort
    expected_denominator <- fixture$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]]$denominator
    testthat::expect_identical(collected$body$chunks[[1L]]$analysis_blocks[[1L]]$denominator,
                               expected_denominator)
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
