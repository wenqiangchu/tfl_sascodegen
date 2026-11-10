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
           counting_unit = "distinct_subject",
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

testthat::test_that("digits resolution is emitted into SAS, not resolved on the host", {
  # Digits are resolved at run time: base_digits comes from the data (see
  # continuous.R), so the host cannot compute the final count for a relative value.
  # The generated program therefore carries the mode and the offset, and SAS decides.
  # These assertions replace tests of a host-side resolver that no consumer called.
  source <- paste(statistic_digits_source(), collapse = "
")
  # Absolute: take the value as written.
  testthat::expect_match(source,
                         "if digits_mode = 'absolute' then resolved_digits = digits_value;",
                         fixed = TRUE)
  # Relative: offset from the per-node base digits, defaulting to zero when absent.
  testthat::expect_match(source,
                         "then resolved_digits = coalesce(base_digits, 0) + digits_value;",
                         fixed = TRUE)
  # Negative results are a visible error and the cell becomes non-estimable rather
  # than silently printing a negative number of decimals.
  testthat::expect_match(source,
                         "putlog 'ERROR: [USER] Relative digits resolved to a negative value.'",
                         fixed = TRUE)
  testthat::expect_match(source, "estimable = 0; resolved_digits = .;", fixed = TRUE)
})

testthat::test_that("a relative and an absolute digits value reach the key map intact", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "portrait",
                        page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(list(id = "t1", population_id = "p1", header_id = "h",
                       template_id = "t1")),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(list(
      id = "k1", type = "continuous_summary", source_data = "adam.ade",
      counting_unit = "record", analysis_variable = "AVAL",
      rows = list(list(id = "r1", type = "analysis", label = "L",
                       cell_format = "{mean} ({sd})",
                       statistics = list(list(id = "mean", digits = "+1"),
                                         list(id = "sd", digits = 2L))))
    ))))))
  parsed <- parse_bundle_value(bundle)
  testthat::expect_identical(parsed$errors, list())
  generated <- generate_table_source(parsed$value, "t1", default_chunk_registry())
  testthat::expect_true(generated$passed)
  # The key map carries the mode and the raw offset, which is what SAS consumes.
  testthat::expect_match(generated$source,
                         '|"mean"|1|"relative"|1|', fixed = TRUE)
  testthat::expect_match(generated$source,
                         '|"sd"|2|"absolute"|2|', fixed = TRUE)
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
           counting_unit = "distinct_subject",
           analysis_variable = "AGE", rows = list(list(
             id = "r1", type = "analysis", label = "Age", statistics = list(list(id = "mean", digits = 1L)),
             cell_format = "{mean}"
           ))),
      list(id = "weight", type = "continuous_summary", source_data = "adam.adsl",
           counting_unit = "distinct_subject",
           analysis_variable = "WEIGHT", rows = list(list(
             id = "r2", type = "analysis", label = "Weight", statistics = list(list(id = "mean", digits = 1L)),
             cell_format = "{mean}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  # The guard runs on the combined pre-merge input, because the membership
  # join below duplicates each source record once per header column.
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("proc sort data=_TFL_CPRE_001 out=_TFL_GUARD_C001", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_match(result$source, "by chunk_order USUBJID;", fixed = TRUE)
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("create table _TFL_CMERGE_001 as", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_match(result$source, "on s.chunk_order = b.chunk_order and s.USUBJID = m.USUBJID;",
                         fixed = TRUE)
  testthat::expect_match(result$source, "set _TFL_CIN_001_001 _TFL_CIN_001_002;", fixed = TRUE)
})
