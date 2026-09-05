testthat::test_that("hierarchical emitter keeps container scope and static-before-dynamic order", {
  block <- list(
    id = "a1", anchor_level = "l1", placement = "same_row",
    type = "continuous_summary", counting_unit = "distinct_subject",
    analysis_variable = "AGE", rows = list(list(
      id = "r1", type = "analysis", label = "Mean",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ))
  )
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(list(
      id = "hier", type = "hierarchical_summary", source_data = "adam.adae",
      source_contract = list(grain = "record", subject_key = "USUBJID",
                             record_key = c("USUBJID", "AESEQ"), duplicate_policy = "error"),
      levels = list(list(id = "l1", variable = "SOC", order_variable = "SOCN",
                         order_direction = "asc", node_role = "label",
                         missing_policy = "exclude")),
      analysis_blocks = list(block)
    )))))
  )
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "Discover hierarchical level 1 nodes", fixed = TRUE)
  testthat::expect_match(result$source, "group_path", fixed = TRUE)
  testthat::expect_match(result$source, "runtime_row_id", fixed = TRUE)
  testthat::expect_match(result$source, "static rows before dynamic children", fixed = TRUE)
  testthat::expect_match(result$source, "Nested primitive type", fixed = TRUE)
  testthat::expect_match(result$source, "Execute nested primitive analysis for node scope", fixed = TRUE)
  testthat::expect_match(result$source, "proc means", fixed = TRUE)
  testthat::expect_match(result$source, "Map nested primitive results to hierarchical identities", fixed = TRUE)
  testthat::expect_match(result$source, "level_component = cats(lengthn", fixed = TRUE)
  testthat::expect_match(result$source, "WARNING: [USER] duplicate_key", fixed = TRUE)
  testthat::expect_match(result$source, "analysis_id = 'a1';", fixed = TRUE)
  testthat::expect_match(result$source, "runtime_row_id = cats(node_key", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_HSTAT_001;", fixed = TRUE)
  testthat::expect_match(result$source, "out=_TFL_HFLAT_001", fixed = TRUE)
  testthat::expect_match(result$source, "set _TFL_HNREND_001;", fixed = TRUE)
  testthat::expect_match(result$source, "data _TFL_HMEM_001;", fixed = TRUE)
  testthat::expect_match(result$source, "merge _TFL_HMEM_001(in=membership)", fixed = TRUE)
  testthat::expect_match(result$source, "set _TFL_HNODE_001;", fixed = TRUE)
  testthat::expect_match(result$source, "Materialize the deepest parent-child node paths", fixed = TRUE)
  testthat::expect_match(result$source, "class chunk_order column_order node_key;", fixed = TRUE)
  testthat::expect_match(result$source, "Overlay hierarchical identity fields on nested long-form rows", fixed = TRUE)
  testthat::expect_match(result$source, "analysis_id = 'a1';", fixed = TRUE)
  testthat::expect_match(result$source, "row_role = 'dynamic';", fixed = TRUE)
  testthat::expect_match(result$source, "by group_path row_role block_order row_order sort_key;", fixed = TRUE)
  testthat::expect_true(length(grep("parent_node_key", result$source, fixed = TRUE)) >= 0L)
  testthat::expect_true(length(regmatches(result$source,
                                          gregexpr("proc sort data=_TFL_HNODE_001", result$source, fixed = TRUE))[[1L]]) >= 1L)
})
