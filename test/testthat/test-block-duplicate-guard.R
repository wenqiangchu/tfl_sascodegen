guard_by_lines <- function(source) {
  lines <- strsplit(source, "\n", fixed = TRUE)[[1]]
  starts <- grep("out=_TFL_GUARD_", lines)
  if (!length(starts)) return(character())
  vapply(starts, function(index) {
    hit <- grep("^  by ", lines[index:min(index + 2L, length(lines))], value = TRUE)
    if (!length(hit)) NA_character_ else trimws(hit[[1L]])
  }, character(1L))
}

base_bundle <- function(chunk) {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "all", label = "All", condition = "1", display_order = 1L,
                               width = 1, alignment = "center")
                        ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(chunk))))
  )
}

categorical_chunk <- function(unit, distinct_key = NULL) {
  chunk <- list(
    id = "sex", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
    counting_unit = unit,
    denominator = list(type = "header_population"),
    rows = list(list(
      id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
      statistics = list(list(id = "n")), cell_format = "{n}"
    ))
  )
  if (!is.null(distinct_key)) chunk$distinct_key <- distinct_key
  chunk
}

continuous_chunk <- function(unit, distinct_key = NULL) {
  chunk <- list(
    id = "age", type = "continuous_summary", source_data = "adam.adsl",
    counting_unit = unit, analysis_variable = "AGE",
    rows = list(list(
      id = "r1", type = "analysis", label = "Age",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ))
  )
  if (!is.null(distinct_key)) chunk$distinct_key <- distinct_key
  chunk
}

testthat::test_that("record counting emits no duplicate guard and no source key table", {
  for (chunk in list(categorical_chunk("record"), continuous_chunk("record"))) {
    result <- generate_table_source(base_bundle(chunk), "t1", include_duplicate_check = TRUE)
    testthat::expect_true(result$passed)
    testthat::expect_length(guard_by_lines(result$source), 0L)
    testthat::expect_false(grepl("duplicate_key", result$source, fixed = TRUE))
    testthat::expect_false(grepl("_TFL_KKEY_", result$source, fixed = TRUE))
  }
})

testthat::test_that("distinct-subject counting guards the subject key per block", {
  categorical <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                      include_duplicate_check = TRUE)
  continuous <- generate_table_source(base_bundle(continuous_chunk("distinct_subject")), "t1",
                                      include_duplicate_check = TRUE)
  testthat::expect_equal(guard_by_lines(categorical$source), "by chunk_order USUBJID;")
  testthat::expect_equal(guard_by_lines(continuous$source), "by chunk_order USUBJID;")
})

testthat::test_that("distinct-key counting guards the declared key per block", {
  keys <- c("USUBJID", "VISIT")
  categorical <- generate_table_source(
    base_bundle(categorical_chunk("distinct_key", keys)), "t1", include_duplicate_check = TRUE)
  continuous <- generate_table_source(
    base_bundle(continuous_chunk("distinct_key", keys)), "t1", include_duplicate_check = TRUE)
  expected <- "by chunk_order USUBJID VISIT;"
  testthat::expect_equal(guard_by_lines(categorical$source), expected)
  testthat::expect_equal(guard_by_lines(continuous$source), expected)
})

testthat::test_that("per-block guards omit column_order while dedup keys keep it", {
  result <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                  include_duplicate_check = TRUE)
  testthat::expect_false(grepl("column_order", paste(guard_by_lines(result$source),
                                                     collapse = " "), fixed = TRUE))
  # Header expansion would otherwise report one source duplicate once per column.
  testthat::expect_match(result$source,
                         "by chunk_order column_order node_key USUBJID;", fixed = TRUE)
})

testthat::test_that("duplicate checking can be switched off entirely", {
  result <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                  include_duplicate_check = FALSE)
  testthat::expect_length(guard_by_lines(result$source), 0L)
  testthat::expect_false(grepl("duplicate_key", result$source, fixed = TRUE))
})
