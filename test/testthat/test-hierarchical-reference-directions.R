source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# Two reference directions in a hierarchical chunk were only checked one way, and one
# positional limit was never checked at all.
#
# Q5: result_sort.metric names a block, a row and a statistic. The existence of each
# was verified, but not that the block is anchored at the level that carries the sort.
# If it is anchored elsewhere, the sort key never matches the node it is applied to and
# the ordering silently degrades to declaration order -- a wrong report, not an error.
# Separately, column_order holds 1-based header column positions, and a positive value
# beyond the header column count addresses no column at all.
#
# Q6: node_analysis_id names a same_row block that must be anchored at the level. The
# forward direction was checked; the reverse was not. An unreferenced same_row block is
# still analysed -- its cells are computed and paid for -- but never rendered, because a
# same_row block only appears on its anchor level's node row.
chunk_bundle <- function(level_ids = c("l1"), anchor = "l1", placement = "same_row",
                         node_analysis_id = "a1", result_sort = NULL,
                         extra_blocks = list(), column_count = 1L,
                         extra_levels = list()) {
  columns <- lapply(seq_len(column_count), function(index) list(
    id = sprintf("c%d", index), label = sprintf("C%d", index), condition = "1",
    display_order = as.integer(index), width = 1, alignment = "center"
  ))
  level <- list(id = "l1", variable = "SOC", order_variable = "SOC",
                order_direction = "asc", missing_policy = "exclude")
  if (!is.null(node_analysis_id)) {
    level$node_role <- "analysis"
    level$node_analysis_id <- node_analysis_id
  } else {
    level$node_role <- "label"
  }
  if (!is.null(result_sort)) level$result_sort <- result_sort
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adae",
                        orientation = "portrait", page_rows = 22L,
                        columns = columns)),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(list(
      id = "k1", type = "hierarchical_summary", source_data = "adam.adae",
      levels = c(list(level), extra_levels),
      analysis_blocks = c(list(list(
        id = "a1", anchor_level = anchor, placement = placement,
        type = "continuous_summary",
        counting_unit = "record", analysis_variable = "AVAL",
        rows = list(list(id = "r1", type = "analysis", label = "Mean",
                         statistics = list(list(id = "mean", digits = 1L)),
                         cell_format = "{mean}"))
      )), extra_blocks)
    ))))))
}

parse_chunk <- function(...) {
  parse_bundle_value(do.call(new_metadata_bundle, chunk_bundle(...)))
}

error_paths <- function(result) vapply(result$errors, function(x) x$path, "")

testthat::test_that("a result_sort metric must name a block anchored at the level", {
  sorted <- list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = list(1L), direction = "asc"
  )
  # Anchor and sort on the same level: valid.
  testthat::expect_identical(parse_chunk(result_sort = sorted)$errors, list())

  # Sort on a second level while the block is anchored at the first. The block exists
  # and its row and statistic exist, so every existence check passes, yet the sort key
  # can never match the second level's nodes and the ordering silently falls back to
  # declaration order. That is the case this check exists for.
  second <- list(id = "l2", variable = "PT", order_variable = "PT",
                 order_direction = "asc", missing_policy = "exclude",
                 node_role = "label", result_sort = sorted)
  paths <- error_paths(parse_chunk(extra_levels = list(second)))
  testthat::expect_true(any(grepl("result_sort", paths)))

  # A metric naming a block that does not exist stays an error as before.
  unknown <- sorted
  unknown$metric$analysis_id <- "nope"
  testthat::expect_true(any(grepl("result_sort", error_paths(parse_chunk(result_sort = unknown)))))
})

testthat::test_that("column_order may not exceed the header column count", {
  sorted <- function(position) list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = list(position), direction = "asc"
  )
  # Two header columns: positions 1 and 2 are addressable, 3 is not. This is checked
  # before generation, because a template can be attached to a header with fewer columns
  # after import, so an import-time check alone would not hold.
  from_import <- function(position) {
    snapshot <- do.call(new_metadata_bundle, chunk_bundle(result_sort = sorted(position),
                                                         column_count = 2L))
    validate_sort_column_positions(snapshot$templates[[1L]], snapshot$headers[[1L]])
  }
  testthat::expect_identical(from_import(2L), list())
  for (too_far in c(3L, 10L)) {
    messages <- vapply(from_import(too_far), function(x) x$message, "")
    testthat::expect_true(length(messages) > 0L, label = as.character(too_far))
    testthat::expect_true(any(grepl("column_order", messages)),
                          label = as.character(too_far))
  }
  # Zero keeps its special meaning (sort after the numbered columns) and is not a
  # position, so it stays allowed regardless of column count.
  zero_last <- list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = list(1L, 0L), direction = "asc"
  )
  snapshot <- do.call(new_metadata_bundle, chunk_bundle(result_sort = zero_last,
                                                       column_count = 1L))
  testthat::expect_identical(
    validate_sort_column_positions(snapshot$templates[[1L]], snapshot$headers[[1L]]),
    list()
  )
})

testthat::test_that("generation refuses an out-of-range sort column before emitting source", {
  # The checker is wired into generate_table_source(), not only exposed as a helper, so a
  # bundle whose template carries a position beyond its header's column count fails the
  # generation boundary instead of producing source that reads a nonexistent column.
  bundle <- do.call(new_metadata_bundle, chunk_bundle(result_sort = list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = list(9L), direction = "asc"
  ), column_count = 1L))
  bundle$tables <- list(list(id = "t1", population_id = "p1", header_id = "h",
                            template_id = "t1"))
  result <- generate_table_source(bundle, "t1")
  testthat::expect_false(result$passed)
  codes <- vapply(result$errors, function(x) x$code, "")
  testthat::expect_true("generation_sort_column_invalid" %in% codes)
  messages <- vapply(result$errors, function(x) x$message, "")
  testthat::expect_true(any(grepl("column_order", messages)))

  # A position inside the header is accepted and source is produced.
  ok <- do.call(new_metadata_bundle, chunk_bundle(result_sort = list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = list(1L), direction = "asc"
  ), column_count = 1L))
  ok$tables <- list(list(id = "t1", population_id = "p1", header_id = "h",
                        template_id = "t1"))
  testthat::expect_true(generate_table_source(ok, "t1")$passed)
})

testthat::test_that("a same_row block must be referenced by its anchor level", {
  # Referenced: fine.
  testthat::expect_identical(parse_chunk()$errors, list())

  # Unreferenced: the block would be analysed but never rendered.
  paths <- error_paths(parse_chunk(node_analysis_id = NULL))
  testthat::expect_true(any(grepl("analysis_blocks", paths)))

  # A below block does not need a node_analysis_id reference, because it renders as its
  # own static rows under the node rather than on the node row.
  below <- parse_chunk(
    placement = "below", node_analysis_id = NULL,
    extra_blocks = list()
  )
  testthat::expect_identical(below$errors, list())
})

testthat::test_that("the unreferenced check names the block and its anchor level", {
  result <- parse_chunk(node_analysis_id = NULL)
  messages <- vapply(result$errors, function(x) x$message, "")
  testthat::expect_true(any(grepl("a1", messages, fixed = TRUE)))
  testthat::expect_true(any(grepl("l1", messages, fixed = TRUE)))
})
