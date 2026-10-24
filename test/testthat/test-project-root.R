testthat::test_that("app.R resolves the repository root independent of the working directory", {
  app_file <- file.path(project_root, "app.R")
  app_lines <- readLines(app_file)

  # Extract only the resolver; this asserts path derivation, not Shiny startup.
  start <- which(grepl("^locate_project_root <- function", app_lines))
  options_line <- which(grepl("^options\\(tfl_sascodegen_root", app_lines))
  testthat::expect_length(start, 1L)
  testthat::expect_length(options_line, 1L)
  stop <- start + which(app_lines[start:(options_line - 1L)] == "}")[1] - 1L
  resolver <- eval(parse(text = paste(app_lines[start:stop], collapse = "\n")))

  expected <- normalizePath(project_root, mustWork = TRUE)

  # The sourced file itself identifies the root, whatever the working directory.
  testthat::expect_identical(resolver(app_file), expected)

  # A file nested in the source tree still walks up to the same root.
  testthat::expect_identical(
    resolver(file.path(project_root, "src", "ui", "metadata_editor_generation.R")),
    expected
  )

  # A nested working directory resolves by walking upwards.
  nested <- normalizePath(file.path(project_root, "src", "ui"), mustWork = TRUE)
  previous <- setwd(nested)
  on.exit(setwd(previous), add = TRUE)
  testthat::expect_identical(resolver(getwd()), expected)

  # An unrelated location has no markers, so the working directory is the fallback.
  unrelated <- withr::local_tempdir()
  testthat::expect_identical(resolver(unrelated), normalizePath(getwd(), mustWork = TRUE))
})

testthat::test_that("runtime assets exist where the download package expects them", {
  assets <- file.path(project_root, "assets")
  testthat::expect_true(file.exists(file.path(assets, "demo_metadata.zip")))
  testthat::expect_true(file.exists(file.path(assets, "user-guide.md")))

  listing <- zip::zip_list(file.path(assets, "demo_metadata.zip"))$filename
  testthat::expect_true("manifest.yaml" %in% listing)
  testthat::expect_true(any(grepl("^templates/", listing)))
})
