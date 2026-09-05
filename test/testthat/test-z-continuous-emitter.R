testthat::test_that("default continuous emitter generates one MEANS batch and long-form stages", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "&ADSL", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl",
           analysis_variable = "AGE", rows = list(list(
             id = "r", type = "analysis", label = "Mean",
             statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_length(regmatches(result$source,
                                     gregexpr("proc means", result$source, fixed = TRUE))[[1L]], 1L)
  testthat::expect_match(result$source, "class chunk_order column_order;", fixed = TRUE)
  testthat::expect_match(result$source, "N=_n MEAN=_mean STD=_sd MEDIAN=_median Q1=_q1 Q3=_q3 MIN=_min MAX=_max",
                         fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_STAT_001;", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_REND_001;", fixed = TRUE)
  testthat::expect_match(result$source, "set adam.adsl;", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_CIN_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_CIN_001;\n  set _TFL_CIN_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "ROUND", fixed = TRUE)
  testthat::expect_match(result$source, "PUTN", fixed = TRUE)
  testthat::expect_match(result$source, "tranwrd", ignore.case = TRUE)
  testthat::expect_match(result$source, "common long-form statistic identity", fixed = TRUE)
  testthat::expect_match(result$source, "complete chunk/row/header/statistic expected-cell skeleton", fixed = TRUE)
  testthat::expect_match(result$source, "infile datalines dlm='|' dsd truncover;", fixed = TRUE)
  testthat::expect_match(result$source, "input chunk_id :$128. row_id :$128.", fixed = TRUE)
  testthat::expect_match(result$source, "if missing(cell_text) then cell_text = '';", fixed = TRUE)
  testthat::expect_match(result$source, "resolved_digits", fixed = TRUE)
  testthat::expect_match(result$source, "estimable = 0 then token = 'NE'", fixed = TRUE)
})

testthat::test_that("relative digits resolve from base digits and reject negative results", {
  testthat::expect_identical(resolve_relative_digits(3L, 2L), 2L)
  testthat::expect_identical(resolve_relative_digits(3L, "+2"), 5L)
  testthat::expect_identical(resolve_relative_digits(3L, "-2"), 1L)
  testthat::expect_error(resolve_relative_digits(1L, "-2"), "negative")
})
