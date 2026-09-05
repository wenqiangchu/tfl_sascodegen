testthat::test_that("Shiny shell exposes core actions and failure feedback", {
  testthat::skip_if_not_installed("shinytest2")
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
  app$expect_screenshot()
  app$click("generate")
  app$wait_for_idle(1000)
  app$expect_screenshot()
  app$click("cancel")
  app$click("download_bundle")
})
