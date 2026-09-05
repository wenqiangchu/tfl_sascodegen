testthat::test_that("default categorical emitter generates event input and one FREQ batch", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", columns = list(
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
  testthat::expect_match(result$source, "row_order = 0; output;", fixed = TRUE)
  testthat::expect_match(result$source, "row_order = 1;", fixed = TRUE)
  testthat::expect_match(result$source, "tables chunk_order*row_order*column_order / out=", fixed = TRUE)
  testthat::expect_match(result$source, "pct = 100 * numerator / denominator", fixed = TRUE)
  testthat::expect_match(result$source, "estimable = 0", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_KIN_001_001;", fixed = TRUE)
  testthat::expect_match(result$source, "tranwrd", ignore.case = TRUE)
  testthat::expect_match(result$source, "statistic_id = 'pct' and estimable = 0", fixed = TRUE)
  testthat::expect_match(result$source, "cell_text = tranwrd(cell_format", fixed = TRUE)
  testthat::expect_match(result$source, "Literal percent characters remain unchanged", fixed = TRUE)
})

testthat::test_that("exclusive categorical emitter adds a nonblocking overlap guard", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", columns = list(
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
})
