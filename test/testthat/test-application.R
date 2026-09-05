testthat::test_that("application orchestration delegates workspace boundaries", {
  workspace <- new_empty_workspace()
  exported <- application_export_bundle(workspace)
  testthat::expect_true(exported$passed)
  testthat::expect_s3_class(exported$value, "CanonicalArchiveBytes")
  testthat::expect_true(is.raw(exported$value$bytes))

  invalid <- application_generate_source(workspace, "")
  testthat::expect_false(invalid$passed)
  testthat::expect_identical(invalid$errors[[1L]]$code, "generation_table_invalid")

  discarded <- application_discard_draft(workspace)
  testthat::expect_true(discarded$passed)
})
