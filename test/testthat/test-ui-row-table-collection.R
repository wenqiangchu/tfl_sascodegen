source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)

# The row table is a data frame with one row per bundle row and a hidden
# .row_id column. rows_from_editor_data() turns it back into bundle rows.
row_table_fixture <- function() {
  data.frame(
    .row_id = c("row_001", "row_002"),
    type = c("analysis", "label"),
    label = c("Mean (SD)", "Additional"),
    indent_level = c(0L, 1L),
    condition = c("SAFFL = 'Y'", NA_character_),
    cell_format = c("{mean} ({sd})", NA_character_),
    statistics = c("mean sd", NA_character_),
    digits = c("1 1", NA_character_),
    statistics_text = c("mean sd", NA_character_),
    stringsAsFactors = FALSE
  )
}

testthat::test_that("row collection keeps analysis fields on analysis rows", {
  rows <- rows_from_editor_data(row_table_fixture())
  testthat::expect_length(rows, 2L)

  analysis <- rows[[1L]]
  testthat::expect_identical(analysis$id, "row_001")
  testthat::expect_identical(analysis$type, "analysis")
  testthat::expect_identical(analysis$condition, "SAFFL = 'Y'")
  testthat::expect_identical(analysis$cell_format, "{mean} ({sd})")
  testthat::expect_identical(vapply(analysis$statistics, `[[`, "", "id"),
                             c("mean", "sd"))
  testthat::expect_identical(analysis$statistics[[1L]]$digits, 1L)
})

testthat::test_that("row collection drops analysis-only fields from a label row", {
  # The model allows a label row exactly id, type, label and indent_level
  # (model.R common_fields). Anything else is bundle_unknown_field:
  #   Field 'cell_format' is not declared for a label row.
  # The collector used to write cell_format and statistics onto every row
  # regardless of type, so a chunk containing a label row could not be saved once
  # the row table had been touched.
  rows <- rows_from_editor_data(row_table_fixture())
  label <- rows[[2L]]

  testthat::expect_identical(label$id, "row_002")
  testthat::expect_identical(label$type, "label")
  testthat::expect_identical(label$label, "Additional")
  testthat::expect_identical(label$indent_level, 1L)

  testthat::expect_null(label$statistics)
  testthat::expect_null(label$cell_format)
  testthat::expect_null(label$condition)
})

testthat::test_that("a collected label row is accepted by the model", {
  # The behavioural consequence: the collected rows must survive parsing.
  rows <- rows_from_editor_data(row_table_fixture())
  # continuous_summary declares allow_condition = FALSE on analysis rows, so drop
  # the condition to keep this test about the label row only. Condition handling on
  # analysis rows is a separate concern and unchanged here.
  rows[[1L]]$condition <- NULL
  chunk <- list(
    id = "k1", type = "continuous_summary", source_data = "adam.adsl",
    counting_unit = "distinct_subject", analysis_variable = "AGE", rows = rows
  )
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "portrait",
                        page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(chunk))))
  )
  testthat::expect_identical(parse_bundle_value(bundle)$errors, list())
})

testthat::test_that("missing digit tokens fall back to no declared digits", {
  # Statistics and Digits are positional. The guard was written as
  # `digit_tokens[[j]] %||% "-"`, but %||% is `if (is.null(x)) y else x` and
  # evaluates its left side first, so an out-of-range [[ ]] raised
  #   Error: subscript out of bounds
  # before %||% was ever consulted. Clearing the Digits cell, or adding a
  # statistic without adding a digit, therefore broke the collector -- which
  # draft_status() calls on every observer tick.
  cached <- row_table_fixture()
  cached$digits[1L] <- ""            # Digits cleared entirely
  cached$statistics[1L] <- "mean sd" # two statistics, no digits
  rows <- rows_from_editor_data(cached)

  testthat::expect_identical(vapply(rows[[1L]]$statistics, `[[`, "", "id"),
                             c("mean", "sd"))
  testthat::expect_null(rows[[1L]]$statistics[[1L]]$digits)
  testthat::expect_null(rows[[1L]]$statistics[[2L]]$digits)

  # Fewer tokens than statistics: the extra statistics simply carry no digits.
  cached$digits[1L] <- "1"
  rows <- rows_from_editor_data(cached)
  testthat::expect_identical(rows[[1L]]$statistics[[1L]]$digits, 1L)
  testthat::expect_null(rows[[1L]]$statistics[[2L]]$digits)

  # An explicit "-" placeholder still means "declare no digits", and a relative
  # offset still reaches the model as a string.
  cached$digits[1L] <- "- +1"
  rows <- rows_from_editor_data(cached)
  testthat::expect_null(rows[[1L]]$statistics[[1L]]$digits)
  testthat::expect_identical(rows[[1L]]$statistics[[2L]]$digits, "+1")
})

testthat::test_that("newly added levels and blocks get unique seed ids", {
  # Adding a level or block seeded it with the fixed id "level" or "analysis".
  # reindex_template() then maps old id -> new id with setNames(), which cannot
  # represent duplicates, so every reference to the duplicate resolved to the first.
  # With three levels all seeded "level", a third level pointing at the second came
  # back pointing at the first, and nothing reported it -- the wrong id is a valid
  # level id.
  testthat::expect_identical(new_item_seed_id("level", character()), "level_001")
  testthat::expect_identical(new_item_seed_id("level", "level_001"), "level_002")
  testthat::expect_identical(new_item_seed_id("level", c("level_001", "level_002")),
                             "level_003")

  # An existing id that does not follow the pattern must not be reused.
  testthat::expect_identical(new_item_seed_id("level", "level"), "level_001")
  testthat::expect_identical(new_item_seed_id("level", c("level_002")), "level_001")

  seeds <- character()
  for (i in 1:3) seeds <- c(seeds, new_item_seed_id("level", seeds))
  testthat::expect_identical(seeds, c("level_001", "level_002", "level_003"))
  testthat::expect_identical(anyDuplicated(seeds), 0L)
})

testthat::test_that("unique seed ids keep a nested parent reference pointing at the right level", {
  # The observable consequence of G8: with ids produced by new_item_seed_id() the
  # reference survives reindexing; with the shared seed id it was rebound to the
  # first level and nothing reported it.
  build <- function(ids) {
    levels <- lapply(seq_along(ids), function(k) {
      level <- list(id = ids[[k]], variable = paste0("V", k),
                    order_variable = paste0("V", k), order_direction = "asc",
                    node_role = "label", missing_policy = "exclude")
      if (k == 3L) level$parent_level <- ids[[2L]]
      level
    })
    list(id = "tpl", body = list(stub_header = "S", chunks = list(list(
      id = "c", type = "hierarchical_summary", source_data = "adam.adae",
      levels = levels, analysis_blocks = list()))))
  }
  ids <- character()
  for (i in 1:3) ids <- c(ids, new_item_seed_id("level", ids))
  testthat::expect_identical(ids, c("level_001", "level_002", "level_003"))

  # Reindex the way the save path does and confirm the third level still names the
  # second. The mapping is the same setNames() construction, so a duplicate id here
  # would collapse it.
  out <- build(ids)
  levels <- out$body$chunks[[1L]]$levels
  new_ids <- sprintf("%s_level_%03d", "chunk_001", seq_along(levels))
  map <- stats::setNames(new_ids, vapply(levels, `[[`, "", "id"))
  testthat::expect_identical(length(unique(names(map))), 3L)
  testthat::expect_identical(unname(map[[levels[[3L]]$parent_level]]), new_ids[[2L]])
})
