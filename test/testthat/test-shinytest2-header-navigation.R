testthat::test_that("imported spanning headers navigate cleanly and retain real edit guards", {
  withr::local_envvar(NOT_CRAN = "true")
  chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))
  app <- shinytest2::AppDriver$new(app_dir = project_root, name = "header-span-navigation",
                                  height = 900, width = 1400, variant = "local", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)
  demo <- file.path(project_root, "assets", "demo_metadata.zip")
  bundle <- parse_bundle_archive(readBin(demo, "raw", file.info(demo)$size))$workspace
  bundle$headers[[1L]]$spanning_headers <- list(list(id = "treatment", level = 1L, label = "Treatment"))
  bundle$headers[[1L]]$columns[[1L]]$spanning_header_1 <- "treatment"
  archive <- withr::local_tempfile(fileext = ".zip")
  writeBin(canonical_archive_bytes(bundle)$bytes, archive)
  app$click("upload_metadata")
  app$upload_file(bundle = archive)
  app$click("confirm_import")
  app$wait_for_idle(1000)

  guarded <- function() grepl("Discard the current changes to continue?", app$get_html("body"), fixed = TRUE)
  open_header <- function() {
    app$set_inputs(main_nav = "metadata")
    app$wait_for_idle(300)
    app$set_inputs(metadata_panel = "header")
    app$wait_for_idle(500)
  }
  edit_span <- function(value) {
    # Exercise DT's typed cell-edit event by committing its actual inline editor.
    app$run_js(sprintf(
      "var cell = $('#header_columns_table tbody tr:first-child td:nth-child(7)'); cell.trigger('dblclick'); cell.find('input').val(%s).trigger('blur');",
      jsonlite::toJSON(value, auto_unbox = TRUE)
    ))
    app$wait_for_idle(400)
  }
  open_header()
  testthat::expect_match(app$get_html("#header_columns_table"), "Treatment", fixed = TRUE)
  app$set_inputs(metadata_panel = "population")
  app$wait_for_idle(400)
  testthat::expect_false(guarded())
  # Stop here on regression so later actions do not interact with the modal.
  if (!guarded()) {
    for (destination in c("table_metadata", "template_editor", "generate_sas")) {
      open_header()
      app$set_inputs(main_nav = destination)
      app$wait_for_idle(500)
      testthat::expect_false(guarded(), info = destination)
    }
    open_header()
    app$click("header_save")
    app$wait_for_idle(500)
    app$click(selector = "#header_list table tbody tr:nth-child(2) td:first-child")
    app$wait_for_idle(400)
    testthat::expect_false(guarded())
    app$click(selector = "#header_list table tbody tr:nth-child(1) td:first-child")
    app$wait_for_idle(400)

    edit_span("Changed treatment")
    testthat::expect_match(app$get_html("#header_columns_table"), "Changed treatment", fixed = TRUE)
    app$set_inputs(main_nav = "table_metadata")
    app$wait_for_idle(400)
    testthat::expect_true(guarded())
    app$click("guard_cancel")
    app$wait_for_idle(400)
    edit_span("Treatment")
    app$set_inputs(main_nav = "table_metadata")
    app$wait_for_idle(400)
    testthat::expect_false(guarded())

    open_header()
    app$set_inputs(header_source_data = "work.changed")
    app$set_inputs(metadata_panel = "population")
    app$wait_for_idle(400)
    testthat::expect_true(guarded())
    app$click("guard_discard")
    app$wait_for_idle(400)
    open_header()
    testthat::expect_identical(app$get_value(input = "header_source_data"), "adam.adsl")
    app$set_inputs(main_nav = "generate_sas")
    app$wait_for_idle(400)
    testthat::expect_false(guarded())
  }
})
