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
    load_timeout = 10000
  )
  on.exit(app$stop(), add = TRUE)
  app$click("generate")
  app$wait_for_idle(1000)
  app$click("cancel")
})
