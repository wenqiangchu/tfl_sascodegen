testthat::test_that("upload landing page is present before Shiny connects and gates successful import", {
  withr::local_envvar(NOT_CRAN = "true")
  chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))
  app <- shinytest2::AppDriver$new(app_dir = project_root, name = "initial-upload-gate",
                                  height = 900, width = 1400, variant = "local", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  # A fresh HTTP response contains no reactive renderUI output or socket messages.
  initial <- xml2::read_html(paste(readLines(app$get_url(), warn = FALSE), collapse = "\n"))
  gate <- xml2::xml_find_first(initial, "//*[@id='metadata_gate']")
  content <- xml2::xml_find_first(initial, "//*[@id='metadata_content']")
  testthat::expect_match(xml2::xml_text(gate),
                         "Upload a metadata ZIP bundle to start editing.", fixed = TRUE)
  testthat::expect_match(xml2::xml_attr(content, "style"), "display\\s*:\\s*none")
  testthat::expect_length(xml2::xml_find_all(gate, ".//*[@id='upload_metadata_gate']"), 1L)

  visible <- function(id) isTRUE(app$get_js(sprintf(
    "getComputedStyle(document.getElementById('%s')).display !== 'none'", id
  )))
  expect_landing <- function() {
    testthat::expect_true(visible("metadata_gate"))
    testthat::expect_false(visible("metadata_content"))
  }
  expect_editor <- function() {
    testthat::expect_false(visible("metadata_gate"))
    testthat::expect_true(visible("metadata_content"))
  }
  expect_landing()
  app$set_inputs(main_nav = "table_metadata")
  app$wait_for_idle(300)
  expect_landing()
  app$set_inputs(main_nav = "metadata")
  app$wait_for_idle(300)

  app$click("upload_metadata_gate")
  app$click("cancel_import")
  app$wait_for_idle(300)
  expect_landing()

  malformed <- withr::local_tempfile(fileext = ".zip")
  writeBin(charToRaw("Invalid archive fixture"), malformed)
  app$click("upload_metadata_gate")
  app$upload_file(bundle = malformed)
  app$click("confirm_import")
  app$wait_for_idle(600)
  expect_landing()

  app$click("upload_metadata_gate")
  app$upload_file(bundle = file.path(project_root, "assets", "demo_metadata.zip"))
  app$click("confirm_import")
  app$wait_for_idle(700)
  expect_editor()
  testthat::expect_identical(app$get_value(input = "population_label"), "FAS")
  testthat::expect_match(app$get_html("#download_metadata_ui"), "download_bundle", fixed = TRUE)

  app$click("upload_metadata")
  app$upload_file(bundle = malformed)
  app$click("confirm_import")
  app$wait_for_idle(600)
  expect_editor()
  testthat::expect_identical(app$get_value(input = "population_label"), "FAS")
})
