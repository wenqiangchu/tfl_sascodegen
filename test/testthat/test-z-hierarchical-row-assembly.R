source(file.path(project_root, "test", "fixtures", "sas", "hierarchical_row_assembly", "metadata.R"),
       local = TRUE)

testthat::test_that("hierarchical flattening owns the row counter instead of reading block counters", {
  result <- generate_table_source(row_assembly_fixture(), "ra")
  testthat::expect_true(result$passed)
  # RETAIN alone cannot protect a value that SET loads again for every cell.
  # Keep the exclusion on the input dataset, not on the output DATA statement.
  testthat::expect_true(grepl("set _TFL_HFLAT_001(drop=row_sequence);", result$source, fixed = TRUE))
  testthat::expect_false(grepl("set _TFL_HFLAT_001;", result$source, fixed = TRUE))
  testthat::expect_match(result$source,
    "by order_key;\n  retain row_sequence 0;\n  if first.order_key then row_sequence + 1;",
    fixed = TRUE)
  testthat::expect_match(result$source, "by order_key column_order;", fixed = TRUE)
  testthat::expect_match(result$source, "by chunk_order row_sequence;", fixed = TRUE)
  testthat::expect_match(result$source, "if last.row_sequence then output;", fixed = TRUE)
})

testthat::test_that("row assembly fixtures retain layout and identity through all source paths", {
  for (case in c("basic", "sorted", "multilevel", "mixed", "empty")) {
    bundle <- row_assembly_fixture(case)
    testthat::expect_length(parse_bundle_value(bundle)$errors, 0L)
    source <- generate_table_source(bundle, "ra")
    testthat::expect_true(source$passed, info = case)
    testthat::expect_identical(source$source, generate_table_source(bundle, "ra")$source)
    containers <- if (case == "mixed") c("001", "003") else "001"
    for (suffix in containers) {
      counter <- paste0(
        "set _TFL_HFLAT_", suffix, "(drop=row_sequence);\n",
        "  by order_key;\n  retain row_sequence 0;\n",
        "  if first.order_key then row_sequence + 1;"
      )
      testthat::expect_true(grepl(counter, source$source, fixed = TRUE), info = case)
    }
    testthat::expect_match(source$source,
      "chunk_order row_sequence column_order runtime_row_id row_role hierarchy_level node_key;",
      fixed = TRUE)
    compare <- generate_table_source(bundle, "ra", output_mode = "compare")
    testthat::expect_true(compare$passed)
    testthat::expect_match(compare$source, "set _TFL_HFLAT_001(drop=row_sequence);", fixed = TRUE)
    if (case %in% c("sorted", "multilevel")) {
      testthat::expect_match(source$source, "metric_missing_1 descending metric_1 label_sort", fixed = TRUE)
    }
    if (case == "multilevel") {
      for (marker in c(
        "data _TFL_HLABEL_001_001;", "p.node_order_path as display_parent_path",
        "left join _TFL_HDISP_001_001 as p on n.parent_node_key = p.node_key",
        "node_order_path = cats(display_parent_path, 'C', put(sibling_order, z10.));",
        "order_key = cats(node_order_path, 'A');",
        "order_key = cats(display_order_path, 'B', put(block_order, z10.), put(row_order, z10.));"
      )) testthat::expect_true(grepl(marker, source$source, fixed = TRUE), info = marker)
      testthat::expect_false(grepl("data _TFL_HLABEL_001_002;", source$source, fixed = TRUE))
    }
    if (case == "mixed") {
      testthat::expect_match(source$source,
        "set _TFL_REND_001 _TFL_REND_002 _TFL_REND_003;", fixed = TRUE)
    }
  }
})
