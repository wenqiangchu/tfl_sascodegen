source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# SAS bounds the decimal count of w.d to 0-31 and requires d < w. result_render.R
# emits PUTN(rounded_value, cats('F', 32, '.', resolved_digits)), so the width is
# fixed at 32 and resolved_digits above 31 produces an invalid format. The model
# checked only the lower bound (min_value = 0).
#
# Absolute digits are known at parse time and are bounded there. A relative offset is
# not: the final value is coalesce(base_digits, 0) + digits_value, and base_digits is
# derived from the data at run time, so the offset is bounded to +/-31 at parse time
# and the resolved value is guarded inside the generated program.
digits_bundle <- function(digits) {
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(list(
      id = "k1", type = "continuous_summary", source_data = "adam.adsl",
      counting_unit = "record", analysis_variable = "AVAL",
      rows = list(list(id = "r1", type = "analysis", label = "L",
                       cell_format = "{mean}",
                       statistics = list(list(id = "mean", digits = digits))))
    ))))))
}

parse_digits <- function(digits) {
  parse_bundle_value(do.call(new_metadata_bundle, digits_bundle(digits)))
}

testthat::test_that("an absolute digits value is bounded to the SAS format limit", {
  # 31 is the largest decimal count SAS accepts, and the width is fixed at 32.
  for (value in c(0L, 1L, 31L)) {
    parsed <- parse_digits(value)
    testthat::expect_identical(parsed$errors, list(), label = as.character(value))
    testthat::expect_identical(parsed$value$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$
                                 statistics[[1L]]$digits, as.integer(value),
                               label = as.character(value))
  }
  for (value in c(32L, 100L, 2147483647L)) {
    parsed <- parse_digits(value)
    testthat::expect_true(length(parsed$errors) > 0L, label = as.character(value))
    paths <- vapply(parsed$errors, function(x) x$path, "")
    testthat::expect_true(any(grepl("digits", paths)), label = as.character(value))
  }
})

testthat::test_that("a relative digits offset is bounded to +/-31", {
  for (value in c("+31", "-31", "+0", "+1")) {
    parsed <- parse_digits(value)
    testthat::expect_identical(parsed$errors, list(), label = value)
    testthat::expect_identical(parsed$value$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$
                                 statistics[[1L]]$digits, value, label = value)
  }
  for (value in c("+32", "-32", "+99999999999", "-99999999999")) {
    parsed <- parse_digits(value)
    testthat::expect_true(length(parsed$errors) > 0L, label = value)
    paths <- vapply(parsed$errors, function(x) x$path, "")
    testthat::expect_true(any(grepl("digits", paths)), label = value)
  }
})

testthat::test_that("the generated program guards the resolved digits count", {
  # A relative offset within range can still resolve out of range, because
  # base_digits comes from the data. The guard has to run where the value is known.
  source <- paste(statistic_digits_source(), collapse = "\n")
  testthat::expect_match(source,
    "else if resolved_digits > 31 and not missing(resolved_digits) then do;", fixed = TRUE)
  testthat::expect_match(source,
    "putlog 'ERROR: [USER] Resolved digits exceed the SAS format limit.'", fixed = TRUE)
  # The negative guard stays as it was.
  testthat::expect_match(source,
    "putlog 'ERROR: [USER] Relative digits resolved to a negative value.'", fixed = TRUE)
})
