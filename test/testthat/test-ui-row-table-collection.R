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
