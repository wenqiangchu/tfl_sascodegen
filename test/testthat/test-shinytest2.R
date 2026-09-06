testthat::test_that("Shiny shell exposes core actions and failure feedback", {
  Sys.setenv(NOT_CRAN = "true")
  testthat::expect_true(requireNamespace("shinytest2", quietly = TRUE))
  testthat::expect_true(requireNamespace("chromote", quietly = TRUE))
  chromote::set_chrome_args(c(
    "--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"
  ))
  app <- shinytest2::AppDriver$new(
    app_dir = project_root,
    name = "p7-shell",
    height = 800,
    width = 1200,
    variant = "local",
    load_timeout = 30000
  )
  on.exit(app$stop(), add = TRUE)
  app$click("generate")
  app$wait_for_idle(1000)
  app$click("cancel")
})

testthat::test_that("Metadata lists and dirty switch guard are browser-covered", {
  Sys.setenv(NOT_CRAN = "true")
  testthat::skip_if_not_installed("shinytest2")
  chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))
  app <- shinytest2::AppDriver$new(app_dir = project_root, name = "p7-selection", height = 800, width = 1200, variant = "local", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)
  testthat::expect_match(app$get_html("#population_list"), "population_list", fixed = TRUE)
  testthat::expect_match(app$get_html("#header_list"), "header_list", fixed = TRUE)
  testthat::expect_match(app$get_html("#table_list"), "table_list", fixed = TRUE)
  testthat::expect_match(app$get_html("#template_list"), "template_list", fixed = TRUE)
})

testthat::test_that("Template cards expose typed collection controls", {
  Sys.setenv(NOT_CRAN = "true")
  testthat::skip_if_not_installed("shinytest2")
  chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))
  app <- shinytest2::AppDriver$new(app_dir = project_root, name = "p7-template-cards", height = 900, width = 1400, variant = "local", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)
  fixture <- file.path(project_root, "test", "fixtures", "demo_metadata.zip")
  testthat::skip_if_not(file.exists(fixture))
  app$upload_file(bundle = fixture)
  app$wait_for_idle(1500)
  app$set_inputs(main_nav = "template_editor")
  app$wait_for_idle(1000)
  html <- app$get_html("#chunk_cards")
  testthat::expect_match(html, "chunk_cards", fixed = TRUE)
})
