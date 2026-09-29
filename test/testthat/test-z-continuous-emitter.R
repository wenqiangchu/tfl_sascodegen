testthat::test_that("default continuous emitter generates one MEANS batch and long-form stages", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "&ADSL", orientation = "landscape", columns = list(
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
  testthat::expect_match(result$source, "data _TFL_CPRE_001;\n  set _TFL_CIN_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "by chunk_order USUBJID;", fixed = TRUE)
  testthat::expect_match(result$source, "create table _TFL_CMERGE_001 as", fixed = TRUE)
  testthat::expect_match(result$source, "ROUND", fixed = TRUE)
  testthat::expect_match(result$source, "PUTN", fixed = TRUE)
  testthat::expect_match(result$source, "tranwrd", ignore.case = TRUE)
  testthat::expect_match(result$source, "common long-form statistic identity", fixed = TRUE)
  testthat::expect_match(result$source, "complete chunk/row/header/statistic expected-cell skeleton", fixed = TRUE)
  testthat::expect_match(result$source, '"mean"', fixed = TRUE)
  testthat::expect_match(result$source, '"absolute"', fixed = TRUE)
  testthat::expect_match(result$source, "if last.column_order then output;", fixed = TRUE)
  testthat::expect_match(result$source, "if missing(cell_text) then cell_text = '';", fixed = TRUE)
  testthat::expect_match(result$source, "resolved_digits", fixed = TRUE)
  testthat::expect_match(result$source, "estimable = 0 then token = 'NE'", fixed = TRUE)
  testthat::expect_match(result$source, "from _TFL_KEY_001 as k left join _TFL_CRAW_001 as r", fixed = TRUE)
  testthat::expect_match(result$source, "when ('mean') value = _mean;", fixed = TRUE)
  testthat::expect_match(result$source, "if rounded_value = 0 then rounded_value = 0;", fixed = TRUE)
})

testthat::test_that("relative digits resolve from base digits and reject negative results", {
  testthat::expect_identical(resolve_relative_digits(3L, 2L), 2L)
  testthat::expect_identical(resolve_relative_digits(3L, "+2"), 5L)
  testthat::expect_identical(resolve_relative_digits(3L, "-2"), 1L)
  testthat::expect_error(resolve_relative_digits(1L, "-2"), "negative")
})

testthat::test_that("compatible continuous chunks share one duplicate guard and header merge", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl",
           analysis_variable = "AGE", rows = list(list(
             id = "r1", type = "analysis", label = "Age", statistics = list(list(id = "mean", digits = 1L)),
             cell_format = "{mean}"
           ))),
      list(id = "weight", type = "continuous_summary", source_data = "adam.adsl",
           analysis_variable = "WEIGHT", rows = list(list(
             id = "r2", type = "analysis", label = "Weight", statistics = list(list(id = "mean", digits = 1L)),
             cell_format = "{mean}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("proc sort data=_TFL_CPRE_001", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("create table _TFL_CMERGE_001 as", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_match(result$source, "on s.chunk_order = b.chunk_order and s.USUBJID = m.USUBJID;",
                         fixed = TRUE)
  testthat::expect_match(result$source, "set _TFL_CIN_001_001 _TFL_CIN_001_002;", fixed = TRUE)
})
