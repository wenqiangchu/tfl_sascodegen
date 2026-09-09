testthat::test_that("FDA-style safety fixture covers relative digits and visit/timepoint hierarchy", {
  zip_path <- file.path(project_root, "test", "fixtures", "demo_metadata.zip")
  bytes <- readBin(zip_path, "raw", n = file.info(zip_path)$size)
  imported <- application_import_bundle(new_empty_workspace(), bytes)
  testthat::expect_true(imported$passed)
  ws <- imported$workspace
  testthat::expect_true("vitals_by_visit" %in% vapply(ws$tables, `[[`, "", "id"))
  vitals <- ws$templates[[which(vapply(ws$templates, `[[`, "", "id") == "vitals_by_visit_template")]]
  chunk <- vitals$body$chunks[[1L]]
  testthat::expect_identical(chunk$levels[[1L]]$variable, "PARAMCD")
  testthat::expect_identical(chunk$levels[[2L]]$variable, "AVISIT")
  statistic <- chunk$analysis_blocks[[1L]]$rows[[1L]]$statistics[[2L]]
  testthat::expect_identical(statistic$digits, "+1")
  generated <- application_generate_source(ws, "vitals_by_visit")
  testthat::expect_true(generated$passed)
  testthat::expect_match(generated$value, "PROC MEANS", ignore.case = TRUE)
  testthat::expect_match(generated$value, "AVISIT", fixed = TRUE)
})
