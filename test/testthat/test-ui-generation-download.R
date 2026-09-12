testthat::test_that("generated SAS downloads use the selected table ID and exact source", {
  source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)
  source(file.path(project_root, "src", "ui", "metadata_editor_generation.R"), local = FALSE)

  testthat::expect_identical(
    generated_sas_filename("baseline_characteristics"),
    "baseline_characteristics.sas"
  )

  destination <- tempfile(fileext = ".sas")
  source_text <- c("data work.example;", "  set adam.adsl;", "run;")
  write_generated_sas(source_text, destination)
  testthat::expect_identical(readLines(destination, warn = FALSE), source_text)
})
