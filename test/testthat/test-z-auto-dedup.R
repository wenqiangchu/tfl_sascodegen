# Auto-deduplication keeps the first source record per key when enabled and must
# leave the generated source unchanged when disabled.

report_fixture <- function(orientation = "landscape") {
  new_metadata_bundle(
    populations = list(list(id = "safety", label = "Safety", expression = "SAFFL = 'Y'")),
    headers = list(list(
      id = "treatment", source_data = "adam.adsl", orientation = orientation,
      spanning_headers = list(list(id = "arms", level = 1L, label = "Treatment")),
      columns = list(
        list(id = "a", label = "Arm A", condition = "TRT01AN = 1", display_order = 1L,
             width = 1.25, alignment = "center", spanning_header_1 = "arms"),
        list(id = "all", label = "Overall", condition = "1", display_order = 2L,
             width = 1.5, alignment = "right", spanning_header_1 = "arms")
      )
    )),
    tables = list(list(
      id = "t_demog", population_id = "safety", header_id = "treatment", template_id = "demog",
      custom_code = list(
        before = "/* Project setup before population selection. */\n%let user_before = 1;",
        after = "/* Update the fixed report input. */\ndata WORK._TFL_ASM_001;\n  set WORK._TFL_ASM_001;\nrun;"
      )
    )),
    templates = list(list(id = "demog", body = list(stub_header = "Characteristic", chunks = list(
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl", analysis_variable = "AGE",
           rows = list(
             list(id = "heading", type = "label", label = "Age\\line (years)"),
             list(id = "mean_sd", type = "analysis", label = "Mean (SD)", indent_level = 1L,
                  statistics = list(list(id = "mean", digits = 1L), list(id = "sd", digits = 2L)),
                  cell_format = "{mean} ({sd})")
           ))
    ))))
  )
}

testthat::test_that("auto_dedup defaults to disabled and preserves the previous source", {
  bundle <- report_fixture()
  default <- generate_table_source(bundle, "t_demog")
  explicit_off <- generate_table_source(bundle, "t_demog", auto_dedup = FALSE)
  testthat::expect_true(default$passed)
  testthat::expect_identical(default$source, explicit_off$source)
  testthat::expect_false(grepl("_TFL_DEDUP_", default$source, fixed = TRUE))
  # Existing counting-unit NODUPKEY sorts are unrelated to source deduplication.
  testthat::expect_false(grepl("source record per key", default$source, fixed = TRUE))
})

testthat::test_that("auto_dedup emits a first-record NODUPKEY before the duplicate check", {
  bundle <- report_fixture()
  result <- generate_table_source(bundle, "t_demog", auto_dedup = TRUE)
  testthat::expect_true(result$passed)
  source <- result$source

  testthat::expect_match(source, "proc sort data=_TFL_CPRE_001 out=_TFL_DEDUP_001 nodupkey;", fixed = TRUE)
  testthat::expect_match(source, "/* Keep the first source record per key and drop later duplicates. */",
                         fixed = TRUE)
  # Primitive batches deduplicate by chunk and the batch subject key.
  testthat::expect_match(source, "  by chunk_order USUBJID;", fixed = TRUE)

  # Deduplication must precede the duplicate check so the check reports what remains.
  dedup_position <- regexpr("_TFL_DEDUP_", source, fixed = TRUE)[[1L]]
  guard_position <- regexpr("_TFL_GUARD_", source, fixed = TRUE)[[1L]]
  testthat::expect_gt(dedup_position, 0L)
  testthat::expect_gt(guard_position, dedup_position)

  # The pre-dedup combined source is still built; NODUPKEY reads it into a new data set.
  testthat::expect_match(source, "data _TFL_CPRE_001;", fixed = TRUE)
})

testthat::test_that("auto_dedup and duplicate checks are independent options", {
  bundle <- report_fixture()
  combinations <- list(
    list(dedup = FALSE, check = FALSE),
    list(dedup = FALSE, check = TRUE),
    list(dedup = TRUE, check = FALSE),
    list(dedup = TRUE, check = TRUE)
  )
  for (combination in combinations) {
    result <- generate_table_source(bundle, "t_demog",
                                    include_duplicate_check = combination$check,
                                    auto_dedup = combination$dedup)
    testthat::expect_true(result$passed)
    testthat::expect_identical(
      grepl("_TFL_DEDUP_", result$source, fixed = TRUE), combination$dedup
    )
    testthat::expect_identical(
      grepl("WARNING: [USER] duplicate_key", result$source, fixed = TRUE), combination$check
    )
  }
})

testthat::test_that("auto_dedup applies to categorical source before counting events", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p1", label = "Population", expression = "1")),
    headers = list(list(
      id = "h1", source_data = "adam.adsl", orientation = "landscape",
      columns = list(list(id = "all", label = "All", condition = "1",
                          display_order = 1L, width = 1, alignment = "center"))
    )),
    tables = list(list(id = "t1", population_id = "p1", header_id = "h1",
                       template_id = "t1")),
    templates = list(list(id = "t1", body = list(stub_header = "Group", chunks = list(
      list(id = "c1", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
           denominator = list(type = "header_population"),
           rows = list(list(id = "r1", type = "analysis", label = "Female",
                            condition = "SEX = 'F'",
                            statistics = list(list(id = "n"), list(id = "pct", digits = 1L)),
                            cell_format = "{n} ({pct}%)")))
    ))))
  )
  off <- generate_table_source(bundle, "t1", auto_dedup = FALSE)
  on <- generate_table_source(bundle, "t1", auto_dedup = TRUE)
  testthat::expect_true(off$passed)
  testthat::expect_true(on$passed)
  testthat::expect_false(grepl("_TFL_DEDUP_", off$source, fixed = TRUE))
  testthat::expect_match(on$source, "proc sort data=_TFL_KSRC_001_001 out=_TFL_DEDUP_K001_001 nodupkey;",
                         fixed = TRUE)
  # The event projection must read the deduplicated source, not the raw input.
  testthat::expect_match(on$source, "  set _TFL_DEDUP_K001_001;", fixed = TRUE)
  testthat::expect_match(on$source, "source_row = _n_;", fixed = TRUE)
})

testthat::test_that("auto_dedup applies to hierarchical source before level discovery", {
  bundle <- report_fixture()
  bundle$templates[[1L]]$body$chunks <- list(list(
    id = "c1", type = "hierarchical_summary", source_data = "adam.adae",
    source_contract = list(grain = "record", subject_key = "USUBJID",
                           record_key = c("USUBJID", "AESEQ"), duplicate_policy = "error"),
    levels = list(list(id = "l1", variable = "SOC", order_variable = "SOCN",
                       order_direction = "asc", node_role = "label",
                       missing_policy = "exclude")),
    analysis_blocks = list(list(
      id = "a1", anchor_level = "l1", placement = "below",
      type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
      denominator = list(scope = "current_group", unit = "distinct_subject"),
      rows = list(list(id = "r1", type = "analysis", label = "Mild",
                       condition = "AESEV = 'MILD'",
                       statistics = list(list(id = "n")), cell_format = "{n}"))
    ))
  ))
  off <- generate_table_source(bundle, "t_demog", auto_dedup = FALSE)
  on <- generate_table_source(bundle, "t_demog", auto_dedup = TRUE)
  testthat::expect_true(off$passed)
  testthat::expect_true(on$passed)
  testthat::expect_false(grepl("_TFL_DEDUP_", off$source, fixed = TRUE))
  # Hierarchical source contract keys are used rather than USUBJID alone.
  testthat::expect_match(on$source,
                         "proc sort data=_TFL_HSRC_001 out=_TFL_DEDUP_H001 nodupkey;",
                         fixed = TRUE)
  testthat::expect_match(on$source, "  by USUBJID AESEQ;", fixed = TRUE)
  # Level discovery reads the deduplicated source.
  testthat::expect_match(on$source, "select s.* from _TFL_DEDUP_H001 as s where exists",
                         fixed = TRUE)
})

testthat::test_that("auto_dedup rejects a non-logical option value", {
  bundle <- report_fixture()
  testthat::expect_error(
    generate_table_source(bundle, "t_demog", auto_dedup = "yes"),
    "auto_dedup must be a single non-missing logical value"
  )
  testthat::expect_error(
    new_generation_request(bundle, "t_demog", auto_dedup = NA),
    "auto_dedup must be a single non-missing logical value"
  )
})
