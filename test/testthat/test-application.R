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

testthat::test_that("application orchestration preserves boundary failures", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p1", label = "Population", expression = "1")),
    headers = list(list(id = "h1", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p1", header_id = "h1",
                       template_id = "t1")),
    templates = list(list(id = "t1", body = list(chunks = list(list(
      id = "c1", type = "continuous_summary", source_data = "adam.adsl",
      analysis_variable = "AGE", rows = list(list(
        id = "r1", type = "analysis", label = "Mean",
        statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
      ))
    ))))))
  workspace <- new_metadata_workspace(bundle)

  imported <- application_import_bundle(workspace, charToRaw("not a zip archive"))
  testthat::expect_false(imported$passed)
  testthat::expect_identical(imported$errors[[1L]]$stage, "import")
  testthat::expect_identical(workspace_revision(imported$workspace), 0L)

  draft <- workspace_begin_draft(workspace, "population", "p1")$workspace
  draft_value <- workspace_draft_value(draft)
  draft_value$label <- "Unsaved"
  dirty <- workspace_set_draft(draft, draft_value)$workspace
  blocked <- application_import_bundle(dirty, charToRaw("not a zip archive"))
  testthat::expect_false(blocked$passed)
  testthat::expect_identical(blocked$errors[[1L]]$code, "workspace_draft_dirty")

  invalid_save <- workspace_set_draft(
    workspace_begin_draft(workspace, "population", "p1")$workspace,
    list(id = "p1", expression = "1")
  )$workspace
  saved <- application_save_draft(invalid_save)
  testthat::expect_false(saved$passed)
  testthat::expect_true(any(vapply(saved$errors, function(error) {
    identical(error$code, "workspace_draft_invalid") ||
      identical(error$stage, "workspace")
  }, logical(1L))))

  reference <- application_generate_source(workspace, "missing_table")
  testthat::expect_false(reference$passed)
  testthat::expect_true(any(grepl("table", vapply(reference$errors, `[[`, "", "code"))))

  definitions <- default_chunk_registry()$definitions
  definitions$continuous_summary$emitter <- NULL
  unavailable_registry <- new_chunk_registry(definitions)
  emitter <- application_generate_source(workspace, "t1", unavailable_registry)
  testthat::expect_false(emitter$passed)
  testthat::expect_identical(emitter$errors[[1L]]$code, "generation_emitter_unavailable")
})

testthat::test_that("saved edits survive ZIP export and preserve Report and QC source", {
  archive <- file.path(project_root, "test", "fixtures", "demo_metadata.zip")
  imported <- application_import_bundle(new_empty_workspace(),
    readBin(archive, "raw", n = file.info(archive)$size))
  testthat::expect_true(imported$passed)
  draft <- workspace_begin_draft(imported$workspace, "population", "fas")$workspace
  value <- workspace_draft_value(draft)
  value$expression <- "FASFL = 'Y' and not missing(USUBJID)"
  draft <- workspace_set_draft(draft, value)$workspace
  saved <- application_save_draft(draft)
  testthat::expect_true(saved$passed)
  testthat::expect_false(workspace_is_dirty(saved$workspace))

  exported <- application_export_bundle(saved$workspace)
  testthat::expect_true(exported$passed)
  restored <- application_import_bundle(new_empty_workspace(), exported$value$bytes)
  testthat::expect_true(restored$passed)
  testthat::expect_identical(workspace_saved_snapshot(restored$workspace),
                             workspace_saved_snapshot(saved$workspace))
  repeated <- application_export_bundle(restored$workspace)
  testthat::expect_identical(repeated$value$bytes, exported$value$bytes)

  for (table in c("baseline_characteristics", "ae_by_soc_pt")) {
    for (mode in c("report", "compare")) {
      before <- application_generate_source(saved$workspace, table, output_mode = mode)
      after <- application_generate_source(restored$workspace, table, output_mode = mode)
      testthat::expect_true(before$passed)
      testthat::expect_true(after$passed)
      testthat::expect_identical(after$value, before$value)
      if (table == "baseline_characteristics") {
        testthat::expect_match(after$value, value$expression, fixed = TRUE)
      }
    }
  }
})
