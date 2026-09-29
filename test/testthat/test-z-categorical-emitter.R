testthat::test_that("default categorical emitter generates event input and one FREQ batch", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "sex", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
           denominator = list(type = "header_population"), rows = list(list(
             id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
             statistics = list(list(id = "n"), list(id = "pct", digits = 1L)),
             cell_format = "{n} ({pct}%)"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_length(regmatches(result$source,
                                     gregexpr("proc freq", result$source, fixed = TRUE))[[1L]], 1L)
  testthat::expect_match(result$source, "row_order = 0; output _TFL_KPRE_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "row_order = 1;", fixed = TRUE)
  testthat::expect_match(result$source,
    "if (SEX = 'F') then do; row_order = 1; output _TFL_KPRE_001_001; end;", fixed = TRUE)
  testthat::expect_match(result$source, "tables chunk_order*row_order*column_order / out=", fixed = TRUE)
  testthat::expect_match(result$source, "pct = 100 * numerator / denominator", fixed = TRUE)
  testthat::expect_match(result$source, "estimable = 0", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_KKEY_001_001 _TFL_KPRE_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "create table _TFL_KMERGE_001 as", fixed = TRUE)
  testthat::expect_match(result$source, "tranwrd", ignore.case = TRUE)
  testthat::expect_match(result$source, "if estimable = 0 then token = 'NE'", fixed = TRUE)
  testthat::expect_match(result$source, "cell_text = TRANWRD(cell_text", fixed = TRUE)
  testthat::expect_match(result$source, "complete chunk/row/header/statistic expected-cell skeleton", fixed = TRUE)
  testthat::expect_match(result$source, "from _TFL_KEY_001 as k left join _TFL_KRAW_001 as r", fixed = TRUE)
  testthat::expect_match(result$source, "if statistic_id = 'n' then do; value = numerator; estimable = 1; end;", fixed = TRUE)
  testthat::expect_match(result$source, "Literal percent characters remain unchanged", fixed = TRUE)
  unchecked <- generate_table_source(bundle, "t1", include_duplicate_check = FALSE)
  testthat::expect_true(unchecked$passed)
  testthat::expect_false(grepl("_TFL_GUARD_|duplicate_key", unchecked$source))
  testthat::expect_match(unchecked$source, "pct = 100 * numerator / denominator", fixed = TRUE)
})

testthat::test_that("compatible categorical chunks share one source guard and membership merge", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "sex", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
           denominator = list(type = "header_population"), rows = list(list(
             id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
             statistics = list(list(id = "n")), cell_format = "{n}"
           ))),
      list(id = "race", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
           denominator = list(type = "header_population"), rows = list(list(
             id = "white", type = "analysis", label = "White", condition = "RACE = 'W'",
             statistics = list(list(id = "n")), cell_format = "{n}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("proc sort data=_TFL_KKEY_001 out=", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(result$source,
                                           gregexpr("create table _TFL_KMERGE_001 as", result$source,
                                                    fixed = TRUE))[[1L]]), 1L)
  testthat::expect_match(result$source, "set _TFL_KPRE_001_001 _TFL_KPRE_001_002;", fixed = TRUE)
})

testthat::test_that("categorical scaffold is limited to header-population denominators", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "sex", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
           denominator = list(type = "non_missing", variable = "SEX"), rows = list(list(
             id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
             statistics = list(list(id = "n")), cell_format = "{n}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_false(grepl("where b.chunk_order in", result$source, fixed = TRUE))
})

testthat::test_that("exclusive categorical emitter adds a nonblocking overlap guard", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(
      list(id = "sex", type = "categorical_summary_exclusive", source_data = "adam.adsl",
           denominator = list(type = "header_population"), rows = list(list(
             id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
             statistics = list(list(id = "n")), cell_format = "{n}"
           )))
    ))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "exclusive_overlap", fixed = TRUE)
  testthat::expect_match(result$source, "WARNING: [USER] exclusive_overlap", fixed = TRUE)
  testthat::expect_match(result$source, "proc freq", fixed = TRUE)
  unchecked <- generate_table_source(bundle, "t1", include_duplicate_check = FALSE)
  testthat::expect_true(unchecked$passed)
  testthat::expect_false(grepl("_TFL_GUARD_|duplicate_key", unchecked$source))
  testthat::expect_match(unchecked$source, "WARNING: [USER] exclusive_overlap", fixed = TRUE)
})
