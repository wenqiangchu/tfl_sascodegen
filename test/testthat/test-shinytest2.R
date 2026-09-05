testthat::test_that("Shiny shell exposes core actions and failure feedback", {
  testthat::skip_if_not_installed("shinytest2")
  app <- shinytest2::AppDriver$new(
    app_dir = project_root,
    name = "p7-shell",
    height = 800,
    width = 1200,
    load_timeout = 10000
  )
  on.exit(app$stop(), add = TRUE)
  app$expect_text("status", "Ready.")
  app$click("generate")
  app$wait_for_idle(1000)
  app$expect_text("status", "Generation failed")
  app$expect_screenshot()
})
