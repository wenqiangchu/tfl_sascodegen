workspace_fixture_bundle <- function() {
  continuous_rows <- list(
    list(
      id = "old_row_1", type = "analysis", label = "Mean",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ),
    list(id = "old_row_2", type = "label", label = "Additional")
  )
  same_row <- list(
    id = "old_analysis_1", anchor_level = "old_level_1", placement = "same_row",
    type = "continuous_summary", counting_unit = "distinct_subject",
    analysis_variable = "AGE",
    rows = list(list(
      id = "old_analysis_row_1", type = "analysis", label = "Mean",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ))
  )
  below <- list(
    id = "old_analysis_2", anchor_level = "old_level_1", placement = "below",
    type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
    denominator = list(scope = "current_group", unit = "distinct_subject"),
    rows = list(list(
      id = "old_analysis_row_2", type = "analysis", label = "Subjects",
      condition = "1", statistics = list(list(id = "n")), cell_format = "{n}"
    ))
  )
  hierarchy <- list(
    id = "old_hierarchy", type = "hierarchical_summary", source_data = "adam.adae",
    source_contract = list(
      grain = "record", subject_key = "USUBJID",
      record_key = c("USUBJID", "AESEQ"), duplicate_policy = "error"
    ),
    levels = list(
      list(
        id = "old_level_1", variable = "SOC", order_variable = "SOCN",
        order_direction = "asc",
        result_sort = list(
          metric = list(
            analysis_id = "old_analysis_2", row_id = "old_analysis_row_2",
            statistic_id = "n"
          ),
          column_order = c(1L, 0L), direction = "desc"
        ),
        node_role = "analysis", node_analysis_id = "old_analysis_1",
        missing_policy = "exclude"
      ),
      list(
        id = "old_level_2", variable = "PT", order_variable = "PTN",
        order_direction = "asc", node_role = "label", missing_policy = "label",
        missing_label = "Not coded"
      )
    ),
    analysis_blocks = list(same_row, below)
  )
  continuous <- list(
    id = "old_continuous", type = "continuous_summary", source_data = "adam.adsl",
    analysis_variable = "AGE", rows = continuous_rows
  )
  new_metadata_bundle(
    populations = list(
      list(id = "p1", label = "Safety", expression = "SAFFL = 'Y'"),
      list(id = "p2", label = "Intent-to-treat", expression = "ITTFL = 'Y'")
    ),
    headers = list(list(
      id = "h1", source_data = "&lib..&adsl",
      columns = list(list(
        id = "overall", label = "Overall", condition = "1", display_order = 1L,
        width = 1.2, alignment = "center"
      ))
    )),
    tables = list(list(
      id = "t1", population_id = "p1", header_id = "h1", template_id = "demo"
    )),
    templates = list(list(
      id = "demo", body = list(stub_header = "Characteristic",
                               chunks = list(continuous, hierarchy))
    ))
  )
}

testthat::test_that("workspace draft save, discard, and cancel follow revision rules", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  testthat::expect_s3_class(workspace, "MetadataWorkspace")
  testthat::expect_identical(workspace_revision(workspace), 0L)
  begun <- workspace_begin_draft(workspace, "population", "p1")
  testthat::expect_true(begun$passed)
  draft_workspace <- begun$workspace
  testthat::expect_false(workspace_is_dirty(draft_workspace))
  testthat::expect_identical(draft_workspace$revision$draft_base_revision, 0L)

  draft <- workspace_draft_value(draft_workspace)
  draft$label <- "Safety analysis set"
  updated <- workspace_set_draft(draft_workspace, draft)
  testthat::expect_true(workspace_is_dirty(updated$workspace))
  testthat::expect_identical(workspace_revision(updated$workspace), 0L)
  testthat::expect_identical(
    workspace_saved_snapshot(updated$workspace)$populations[[1L]]$label, "Safety"
  )

  cancelled <- workspace_cancel(updated$workspace)
  testthat::expect_true(workspace_is_dirty(cancelled$workspace))
  testthat::expect_identical(cancelled$workspace$active_draft, updated$workspace$active_draft)

  saved <- workspace_save_draft(cancelled$workspace)
  testthat::expect_true(saved$passed)
  testthat::expect_identical(workspace_revision(saved$workspace), 1L)
  testthat::expect_null(saved$workspace$active_draft)
  testthat::expect_null(saved$workspace$revision$draft_base_revision)
  testthat::expect_identical(saved$workspace$populations[[1L]]$label,
                             "Safety analysis set")

  second <- workspace_begin_draft(saved$workspace, "population", "p1")$workspace
  second_value <- workspace_draft_value(second)
  second_value$label <- "Unsaved"
  second <- workspace_set_draft(second, second_value)$workspace
  discarded <- workspace_discard_draft(second)
  testthat::expect_true(discarded$passed)
  testthat::expect_identical(workspace_revision(discarded$workspace), 1L)
  testthat::expect_null(discarded$workspace$active_draft)
  testthat::expect_null(discarded$workspace$revision$draft_base_revision)
  testthat::expect_identical(discarded$workspace$populations[[1L]]$label,
                             "Safety analysis set")
})

testthat::test_that("failed save preserves saved metadata and the active draft", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  begun <- workspace_begin_draft(workspace, "population", "p1")$workspace
  invalid <- list(id = "p1", expression = "1")
  dirty <- workspace_set_draft(begun, invalid)$workspace
  result <- workspace_save_draft(dirty)
  testthat::expect_false(result$passed)
  testthat::expect_identical(workspace_revision(result$workspace), 0L)
  testthat::expect_identical(result$workspace$populations[[1L]]$label, "Safety")
  testthat::expect_identical(result$workspace$active_draft, dirty$active_draft)
  testthat::expect_true(all(vapply(result$errors, function(item) {
    identical(item$stage, "workspace")
  }, logical(1L))))

  table_target <- workspace_target("table", "t1")
  deferred <- workspace_update(
    workspace, table_target,
    list(id = "t1", population_id = "p1", header_id = "h1",
         template_id = "not_loaded")
  )
  testthat::expect_true(deferred$passed)
  testthat::expect_identical(deferred$workspace$tables[[1L]]$template_id, "not_loaded")
})

testthat::test_that("import is atomic and only failures update parse diagnostics", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  draft <- workspace_begin_draft(workspace, "population", "p1")$workspace
  value <- workspace_draft_value(draft)
  value$label <- "Dirty value"
  draft <- workspace_set_draft(draft, value)$workspace
  before <- workspace_saved_snapshot(draft)
  before_revision <- workspace_revision_value(draft)

  blocked <- workspace_import_bundle(draft, "schema_version: [")
  testthat::expect_false(blocked$passed)
  testthat::expect_identical(blocked$errors[[1L]]$code, "workspace_draft_dirty")
  failed <- workspace_import_bundle(draft, charToRaw("not a zip archive"), allow_dirty = TRUE)
  testthat::expect_false(failed$passed)
  testthat::expect_identical(workspace_saved_snapshot(failed$workspace), before)
  testthat::expect_identical(failed$workspace$active_draft, draft$active_draft)
  testthat::expect_identical(workspace_revision_value(failed$workspace), before_revision)
  testthat::expect_length(failed$workspace$parse_diagnostic, 1L)

  replacement <- workspace_fixture_bundle()
  replacement$populations[[1L]]$label <- "Imported snapshot"
  succeeded <- workspace_import_bundle(
    failed$workspace, canonical_archive_bytes(replacement), allow_dirty = TRUE
  )
  testthat::expect_true(succeeded$passed)
  testthat::expect_identical(workspace_revision(succeeded$workspace), 1L)
  testthat::expect_identical(succeeded$workspace$populations[[1L]]$label,
                             "Imported snapshot")
  testthat::expect_null(succeeded$workspace$active_draft)
  testthat::expect_length(succeeded$workspace$parse_diagnostic, 0L)
})

testthat::test_that("metadata export always uses the saved snapshot", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  draft <- workspace_begin_draft(workspace, "population", "p1")$workspace
  value <- workspace_draft_value(draft)
  value$label <- "Not saved"
  draft <- workspace_set_draft(draft, value)$workspace
  exported <- workspace_export_bundle(draft)
  testthat::expect_true(exported$passed)
  decoded <- parse_bundle_archive(exported$value)
  testthat::expect_true(decoded$passed)
  testthat::expect_identical(decoded$workspace$populations[[1L]]$label, "Safety")
  testthat::expect_true(workspace_is_dirty(exported$workspace))
})

testthat::test_that("referenced top-level objects cannot be deleted", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  blocked <- workspace_delete_impact(workspace, "population", "p1")
  testthat::expect_false(blocked$allowed)
  testthat::expect_identical(blocked$affected_tables, "t1")
  testthat::expect_identical(blocked$errors[[1L]]$code, "workspace_delete_referenced")

  allowed <- workspace_delete_impact(workspace, "population", "p2")
  testthat::expect_true(allowed$allowed)
  pending <- workspace_begin_delete(workspace, "population", "p2")
  testthat::expect_true(pending$passed)
  unconfirmed <- workspace_save_draft(pending$workspace)
  testthat::expect_false(unconfirmed$passed)
  testthat::expect_identical(unconfirmed$errors[[1L]]$code,
                             "workspace_delete_confirmation_required")
  confirmed <- workspace_confirm_delete(pending$workspace)
  deleted <- workspace_save_draft(confirmed$workspace)
  testthat::expect_true(deleted$passed)
  testthat::expect_identical(vapply(deleted$workspace$populations, `[[`, "", "id"), "p1")
  testthat::expect_identical(workspace_revision(deleted$workspace), 1L)
})

testthat::test_that("draft status distinguishes clean updates and pending creates", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  testthat::expect_identical(workspace_draft_status(workspace), "none")
  begun <- workspace_begin_draft(workspace, "population", "p1")
  testthat::expect_identical(workspace_draft_status(begun$workspace), "update_clean")
  updated <- workspace_set_draft(begun$workspace, workspace_draft_value(begun$workspace))
  testthat::expect_identical(workspace_draft_status(updated$workspace), "update_clean")
  created <- workspace_begin_draft(workspace, "population", "p_new", operation = "create",
                                    value = list(id = "p_new", label = "New", expression = "1"))
  testthat::expect_identical(workspace_draft_status(created$workspace), "create_pending")
})

testthat::test_that("immediate delete does not leave a delete draft", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  deleted <- workspace_delete_immediate(workspace, workspace_target("population", "p2"))
  testthat::expect_true(deleted$passed)
  testthat::expect_null(deleted$workspace$active_draft)
  testthat::expect_identical(vapply(deleted$workspace$populations, `[[`, "", "id"), "p1")
})

testthat::test_that("pending create supports explicit discard and save", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  pending <- workspace_begin_draft(workspace, "population", "p_new", operation = "create",
                                    value = list(id = "p_new", label = "New", expression = "1"))
  testthat::expect_true(pending$passed)
  testthat::expect_true("p_new" %in% vapply(workspace_overlay_active_draft(pending$workspace)$populations, `[[`, "", "id"))
  discarded <- workspace_discard_draft(pending$workspace)
  testthat::expect_false("p_new" %in% vapply(discarded$workspace$populations, `[[`, "", "id"))
  saved <- workspace_create(workspace, "population", list(id = "p_new", label = "New", expression = "1"))
  testthat::expect_true(saved$passed)
  testthat::expect_true("p_new" %in% vapply(saved$workspace$populations, `[[`, "", "id"))
  testthat::expect_null(saved$workspace$active_draft)
})

testthat::test_that("position IDs and hierarchical references are rebuilt together", {
  reindexed <- workspace_reindex_bundle_positions(workspace_fixture_bundle())
  chunks <- reindexed$templates[[1L]]$body$chunks
  testthat::expect_identical(vapply(chunks, `[[`, "", "id"),
                             c("demo_001", "demo_002"))
  testthat::expect_identical(
    vapply(chunks[[1L]]$rows, `[[`, "", "id"),
    c("demo_001_001", "demo_001_002")
  )
  hierarchy <- chunks[[2L]]
  testthat::expect_identical(
    vapply(hierarchy$levels, `[[`, "", "id"),
    c("demo_002_level_001", "demo_002_level_002")
  )
  testthat::expect_identical(
    vapply(hierarchy$analysis_blocks, `[[`, "", "id"),
    c("demo_002_analysis_001", "demo_002_analysis_002")
  )
  testthat::expect_identical(hierarchy$levels[[1L]]$node_analysis_id,
                             "demo_002_analysis_001")
  testthat::expect_identical(hierarchy$levels[[1L]]$result_sort$metric$analysis_id,
                             "demo_002_analysis_002")
  testthat::expect_identical(hierarchy$levels[[1L]]$result_sort$metric$row_id,
                             "demo_002_analysis_002_001")
  testthat::expect_identical(hierarchy$analysis_blocks[[1L]]$anchor_level,
                             "demo_002_level_001")
})

testthat::test_that("nested create and move preserve sequence semantics", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  created <- workspace_create(
    workspace, "row", list(type = "label", label = "Created row"),
    template_id = "demo", chunk_id = "old_continuous", position = 2L
  )
  testthat::expect_true(created$passed)
  rows <- created$workspace$templates[[1L]]$body$chunks[[1L]]$rows
  testthat::expect_identical(vapply(rows, `[[`, "", "id"),
                             c("demo_001_001", "demo_001_002", "demo_001_003"))
  testthat::expect_identical(vapply(rows, `[[`, "", "label"),
                             c("Mean", "Created row", "Additional"))

  moved <- workspace_move(
    workspace,
    workspace_target("chunk", "old_hierarchy", template_id = "demo"),
    direction = "up"
  )
  testthat::expect_true(moved$passed)
  chunks <- moved$workspace$templates[[1L]]$body$chunks
  testthat::expect_identical(vapply(chunks, `[[`, "", "type"),
                             c("hierarchical_summary", "continuous_summary"))
  testthat::expect_identical(vapply(chunks, `[[`, "", "id"),
                             c("demo_001", "demo_002"))

  block_moved <- workspace_move(
    moved$workspace,
    workspace_target(
      "analysis_block", "demo_001_analysis_002", template_id = "demo",
      chunk_id = "demo_001"
    ),
    direction = "up"
  )
  testthat::expect_true(block_moved$passed)
  hierarchy <- block_moved$workspace$templates[[1L]]$body$chunks[[1L]]
  testthat::expect_identical(hierarchy$analysis_blocks[[1L]]$type,
                             "categorical_summary_nonexclusive")
  testthat::expect_identical(hierarchy$levels[[1L]]$node_analysis_id,
                             "demo_001_analysis_002")
  testthat::expect_identical(hierarchy$levels[[1L]]$result_sort$metric$analysis_id,
                             "demo_001_analysis_001")
  testthat::expect_identical(hierarchy$levels[[1L]]$result_sort$metric$row_id,
                             "demo_001_analysis_001_001")
})

testthat::test_that("invalid nested parents and move targets return workspace errors", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())

  invalid_level <- workspace_create(
    workspace, "level", list(type = "label", label = "Invalid"),
    template_id = "demo", chunk_id = "old_continuous"
  )
  testthat::expect_false(invalid_level$passed)
  testthat::expect_identical(invalid_level$errors[[1L]]$code,
                             "workspace_target_invalid")
  testthat::expect_identical(workspace_revision(invalid_level$workspace), 0L)
  testthat::expect_null(invalid_level$workspace$active_draft)

  missing_move <- workspace_move(
    workspace,
    workspace_target("chunk", "missing", template_id = "demo"),
    direction = "up"
  )
  testthat::expect_false(missing_move$passed)
  testthat::expect_identical(missing_move$errors[[1L]]$code,
                             "workspace_target_missing")
  testthat::expect_identical(workspace_revision(missing_move$workspace), 0L)

  invalid_position <- workspace_create(
    workspace, "population", list(id = "p3", label = "Other", expression = "1"),
    position = 0L
  )
  testthat::expect_false(invalid_position$passed)
  testthat::expect_identical(invalid_position$errors[[1L]]$code,
                             "workspace_position_invalid")
})

testthat::test_that("nested deletion reindexes remaining positions and references", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  deleted <- workspace_delete(
    workspace,
    workspace_target("chunk", "old_continuous", template_id = "demo"),
    confirm = TRUE
  )
  testthat::expect_true(deleted$passed)
  testthat::expect_identical(workspace_revision(deleted$workspace), 1L)

  chunks <- deleted$workspace$templates[[1L]]$body$chunks
  testthat::expect_identical(vapply(chunks, `[[`, "", "id"), "demo_001")
  hierarchy <- chunks[[1L]]
  testthat::expect_identical(hierarchy$id, "demo_001")
  testthat::expect_identical(
    vapply(hierarchy$levels, `[[`, "", "id"),
    c("demo_001_level_001", "demo_001_level_002")
  )
  testthat::expect_identical(
    vapply(hierarchy$analysis_blocks, `[[`, "", "id"),
    c("demo_001_analysis_001", "demo_001_analysis_002")
  )
  testthat::expect_identical(hierarchy$levels[[1L]]$node_analysis_id,
                             "demo_001_analysis_001")
  testthat::expect_identical(hierarchy$analysis_blocks[[1L]]$anchor_level,
                             "demo_001_level_001")
})

testthat::test_that("object IDs remain immutable during update", {
  workspace <- new_metadata_workspace(workspace_fixture_bundle())
  result <- workspace_update(
    workspace,
    workspace_target("population", "p1"),
    list(id = "renamed", label = "Safety", expression = "SAFFL = 'Y'")
  )
  testthat::expect_false(result$passed)
  testthat::expect_identical(result$errors[[1L]]$code, "workspace_id_immutable")
  testthat::expect_identical(workspace_revision(result$workspace), 0L)
  testthat::expect_identical(result$workspace$populations[[1L]]$id, "p1")
  testthat::expect_true(is.list(result$workspace$active_draft))
  testthat::expect_identical(
    result$workspace$active_draft$draft_value$id,
    "renamed"
  )
})
