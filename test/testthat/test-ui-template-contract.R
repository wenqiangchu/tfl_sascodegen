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
          id = "l", variable = "SOC", format = "visit_fmt",
          node_role = "label", missing_policy = "exclude",
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

# A level driven by `format` must not carry label_variable / order_variable /
# order_direction; the model rejects the combination. The order_direction select
# used to have no blank option, so the browser posted "asc" for every level
# whether or not a format was set, which made a format-driven template impossible
# to save at all. The select now offers a blank choice, and the collector still
# drops the fields defensively: a level whose format was just added can carry
# values forward from its previously saved, format-free shape.
testthat::test_that("a format level saves even when the editor posts order fields", {
  ui_environment <- template_contract_ui_environment()
  fixture <- template_sort_fixture()
  decorated <- ui_environment$decorate_template_ui_ids(fixture$templates[[1L]])

  shiny::testServer(ui_environment$metadata_editor_server_impl, {
    workspace(new_metadata_workspace(fixture))
    metadata_loaded(TRUE)
    active_editor(list(document_type = "template", document_id = "tpl"))
    active_draft(list(operation = "update", original = fixture$templates[[1L]]))
    template_value(decorated)
    # What the browser actually posts when the format is untouched: the blank
    # option, i.e. an empty string.
    session$setInputs(template_stub_header = "Updated SOC",
                      chunk_1_level_1_order_direction = "")

    collected <- collect_template_from_ui(strip_ids = TRUE)
    level <- collected$body$chunks[[1L]]$levels[[1L]]
    testthat::expect_identical(level$format, "visit_fmt")
    testthat::expect_null(level$order_direction)
    testthat::expect_null(level$order_variable)
    testthat::expect_null(level$label_variable)

    save_active("template")
    saved <- workspace_saved_snapshot(workspace())$templates[[1L]]
    testthat::expect_identical(saved$body$stub_header, "Updated SOC")
    testthat::expect_identical(saved$body$chunks[[1L]]$levels[[1L]]$format, "visit_fmt")
    testthat::expect_null(saved$body$chunks[[1L]]$levels[[1L]]$order_direction)
  })
})

# Clearing the format must let the order fields be used again: without a format
# they are required, so dropping them unconditionally would make the level
# unsavable the other way round.
testthat::test_that("clearing the format lets the order fields be saved again", {
  ui_environment <- template_contract_ui_environment()
  fixture <- template_sort_fixture()
  decorated <- ui_environment$decorate_template_ui_ids(fixture$templates[[1L]])

  shiny::testServer(ui_environment$metadata_editor_server_impl, {
    workspace(new_metadata_workspace(fixture))
    metadata_loaded(TRUE)
    active_editor(list(document_type = "template", document_id = "tpl"))
    active_draft(list(operation = "update", original = fixture$templates[[1L]]))
    template_value(decorated)
    session$setInputs(template_stub_header = "Updated SOC",
                      chunk_1_level_1_format = "",
                      chunk_1_level_1_order_variable = "SOC",
                      chunk_1_level_1_order_direction = "desc")

    collected <- collect_template_from_ui(strip_ids = TRUE)
    level <- collected$body$chunks[[1L]]$levels[[1L]]
    testthat::expect_null(level$format)
    testthat::expect_identical(level$order_variable, "SOC")
    testthat::expect_identical(level$order_direction, "desc")

    save_active("template")
    saved <- workspace_saved_snapshot(workspace())$templates[[1L]]
    testthat::expect_identical(saved$body$stub_header, "Updated SOC")
    testthat::expect_null(saved$body$chunks[[1L]]$levels[[1L]]$format)
    testthat::expect_identical(saved$body$chunks[[1L]]$levels[[1L]]$order_variable, "SOC")
    testthat::expect_identical(saved$body$chunks[[1L]]$levels[[1L]]$order_direction, "desc")
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

# The level editor used to say the label and order variables were "ignored" when a
# format was present. The model now rejects that combination outright, so the hint
# must state the rule. A stale hint would send the user to a save that cannot pass.
testthat::test_that("the level editor states that a format excludes label and order fields", {
  source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)
  source(file.path(project_root, "src", "ui", "metadata_editor_template.R"), local = FALSE)
  chunk <- list(id = "c", type = "hierarchical_summary", source_data = "work.events",
                levels = list(), analysis_blocks = list())
  level <- list(id = "l", variable = "SOC", node_role = "label",
                missing_policy = "exclude", format = "soc_fmt")
  with_format <- as.character(level_ui(level, "chunk_1_", 1L, chunk))
  testthat::expect_match(with_format, "cannot be combined with it", fixed = TRUE)
  testthat::expect_match(with_format, "NOTSORTED", fixed = TRUE)
  testthat::expect_false(grepl("are ignored", with_format, fixed = TRUE))

  level$format <- NULL
  level$order_variable <- "SOCN"
  level$order_direction <- "asc"
  without_format <- as.character(level_ui(level, "chunk_1_", 1L, chunk))
  testthat::expect_match(without_format, "needs an order variable", fixed = TRUE)
  testthat::expect_false(grepl("cannot be combined", without_format, fixed = TRUE))
})

# A select with no blank option cannot express "unset", so order_direction could
# never be cleared once set: the browser always had to post asc or desc.
testthat::test_that("the order direction select offers an unset choice", {
  source_text <- paste(readLines(file.path(project_root, "src", "ui",
                                           "metadata_editor_template.R"),
                                 warn = FALSE), collapse = "\n")
  testthat::expect_match(source_text, '"(not set)" = ""', fixed = TRUE)
  # And it defaults to unset rather than to asc.
  testthat::expect_match(source_text,
                         'selected = level$order_direction %||% ""', fixed = TRUE)

  ui_environment <- template_contract_ui_environment()
  fixture <- template_sort_fixture()
  decorated <- ui_environment$decorate_template_ui_ids(fixture$templates[[1L]])

  shiny::testServer(ui_environment$metadata_editor_server_impl, {
    workspace(new_metadata_workspace(fixture))
    metadata_loaded(TRUE)
    active_editor(list(document_type = "template", document_id = "tpl"))
    active_draft(list(operation = "update", original = fixture$templates[[1L]]))
    template_value(decorated)
    # Clearing the select must remove the field rather than pin it to asc.
    session$setInputs(template_stub_header = "Cleared",
                      chunk_1_level_1_order_direction = "")
    collected <- collect_template_from_ui(strip_ids = TRUE)
    testthat::expect_null(collected$body$chunks[[1L]]$levels[[1L]]$order_direction)
  })
})
