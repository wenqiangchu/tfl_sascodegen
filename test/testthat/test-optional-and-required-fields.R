source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# Two consistency defects in how optional and conditionally required fields are handled.
#
# Q9: filter, denominator.expression and rows[].condition are all optional SAS
# expressions that are preserved verbatim and never evaluated by R. A value of only
# whitespace is not an expression, so it means "not provided" -- but filter already
# blanks to NULL while the other two raised "must be non-empty". The same concept was
# treated two ways depending on which field it appeared in.
#
# Q10: add_required_error() already exists and reports bundle_required_field_missing for
# a plain absent field. The conditionally required ones did not use it: an analysis block
# without analysis_variable or denominator, and an analysis row without statistics,
# cell_format or condition, fell through to bundle_structure_invalid ("unsupported
# structure"), which says the value is malformed rather than that a field is absent. A
# caller cannot tell from that code whether to add a field or fix a type.
continuous_bundle <- function(filter = NULL, drop = character()) {
  rows <- list(list(id = "r1", type = "analysis", label = "Mean",
                    statistics = list(list(id = "mean", digits = 1L)),
                    cell_format = "{mean}"))
  chunk <- list(id = "k1", type = "continuous_summary", source_data = "adam.adsl",
                counting_unit = "record", analysis_variable = "AVAL", rows = rows)
  if (!is.null(filter)) chunk$filter <- filter
  for (field in drop) chunk[[field]] <- NULL
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(chunk))))
  )
}

categorical_bundle <- function(expression = NULL, drop_denominator = FALSE,
                               condition = "AGEGR1 = '1'") {
  denominator <- list(scope = "chunk_source", unit = "record")
  if (!is.null(expression)) denominator$expression <- expression
  # cell_format is required on a categorical row; omitting it would fail the fixture for
  # a reason unrelated to what this file checks.
  row <- list(id = "r1", type = "analysis", label = "N",
              statistics = list(list(id = "n")), cell_format = "{n}")
  if (!is.null(condition)) row$condition <- condition
  chunk <- list(
    id = "k1", type = "categorical_summary_exclusive", source_data = "adam.adsl",
    counting_unit = "record", rows = list(row)
  )
  if (!drop_denominator) chunk$denominator <- denominator
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(chunk))))
  )
}

parse_one <- function(bundle) {
  parse_bundle_value(do.call(new_metadata_bundle, bundle))
}

codes <- function(result) vapply(result$errors, function(x) x$code, "")
paths <- function(result) vapply(result$errors, function(x) x$path, "")

testthat::test_that("a whitespace-only optional expression means not provided", {
  # filter already behaved this way.
  blank_filter <- parse_one(continuous_bundle(filter = "   "))
  testthat::expect_identical(blank_filter$errors, list())

  # rows[].condition is required for categorical rows and is the third optional SAS
  # expression; whitespace there must not be an error either.
  blank_condition <- parse_one(categorical_bundle(condition = "  "))
  testthat::expect_identical(blank_condition$errors, list())

  # denominator.expression likewise.
  blank_denominator <- parse_one(categorical_bundle(expression = " \t "))
  testthat::expect_identical(blank_denominator$errors, list())

  # A real expression is still preserved verbatim, including surrounding space.
  kept <- parse_one(categorical_bundle(expression = " AGEGR1 = '1' "))
  testthat::expect_identical(kept$errors, list())
  testthat::expect_identical(
    kept$value$templates[[1L]]$body$chunks[[1L]]$denominator$expression,
    " AGEGR1 = '1' "
  )
})
