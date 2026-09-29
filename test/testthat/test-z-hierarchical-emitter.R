hierarchical_report_fixture <- function() {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape", columns = list(
      list(id = "all", label = "All", condition = "1", display_order = 1L,
           width = 1, alignment = "center")
    ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(list(
      id = "hier", type = "hierarchical_summary", source_data = "adam.adae",
      filter = "SAFFL = 'Y'",
      source_contract = list(grain = "record", subject_key = "USUBJID",
                             record_key = c("USUBJID", "AESEQ"), duplicate_policy = "error"),
      levels = list(
        list(id = "l1", variable = "SOC", order_variable = "SOCN",
             order_direction = "asc", node_role = "label", missing_policy = "exclude"),
        list(id = "l2", variable = "PT", order_variable = "PTN",
             order_direction = "asc", node_role = "label", missing_policy = "exclude")
      ),
      analysis_blocks = list(list(
        id = "a1", anchor_level = "l1", placement = "below",
        type = "continuous_summary", counting_unit = "record",
        analysis_variable = "AGE", rows = list(list(
          id = "r1", type = "analysis", label = "Mean",
          statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
        ))
      ))
    )))))
  )
}

hierarchical_continuous_group_fixture <- function(count = 2L, unit = "record") {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  prototype <- chunk$analysis_blocks[[1L]]
  chunk$analysis_blocks <- lapply(seq_len(count), function(index) {
    block <- prototype
    block$id <- paste0("a", index)
    block$analysis_variable <- paste0("VALUE", index)
    block$counting_unit <- unit
    if (unit == "distinct_key") block$distinct_key <- c("USUBJID", "AESEQ")
    # Local row IDs may repeat across blocks; result ownership must not rely on them.
    block$rows[[1L]]$statistics[[1L]]$digits <- if (index == 1L) 1L else "+1"
    block
  })
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
  bundle
}

hierarchical_source_count <- function(source, text) {
  lengths(regmatches(source, gregexpr(text, source, fixed = TRUE)))
}

testthat::test_that("adjacent continuous blocks share MEANS and retain private result identities", {
  for (count in c(2L, 3L, 4L)) {
    bundle <- hierarchical_continuous_group_fixture(count)
    chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
    chunk$levels[[1L]]$result_sort <- list(
      metric = list(analysis_id = "a2", row_id = "r1", statistic_id = "mean"),
      column_order = c(1L, 0L), direction = "desc"
    )
    chunk$levels[[1L]]$node_role <- "analysis"
    chunk$levels[[1L]]$node_analysis_id <- "a1"
    chunk$analysis_blocks[[1L]]$placement <- "same_row"
    bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
    bundle$headers[[1L]]$columns[[2L]] <- list(
      id = "empty", label = "Empty", condition = "0", display_order = 2L,
      width = 1, alignment = "center"
    )
    result <- generate_table_source(bundle, "t1")
    testthat::expect_true(result$passed)
    source <- result$source
    testthat::expect_equal(hierarchical_source_count(source, "proc means"), 1L)
    testthat::expect_equal(hierarchical_source_count(source, "create table _TFL_HMERGE_001_001 as"), 1L)
    raw_outputs <- sprintf("_TFL_CRAW_%03d", seq_len(count) + 1L)
    testthat::expect_match(source,
      paste0("data ", paste(raw_outputs, collapse = " "), ";"), fixed = TRUE)
    testthat::expect_equal(hierarchical_source_count(source, "set _TFL_HCRAW_001_001"), 1L)
    split_start <- regexpr("set _TFL_HCRAW_001_001", source, fixed = TRUE)[[1L]]
    split_end <- split_start + regexpr("run;", substring(source, split_start), fixed = TRUE)[[1L]]
    result_start <- regexpr("data _TFL_KEY_MAP_002;", source, fixed = TRUE)[[1L]]
    testthat::expect_lt(split_end, result_start)
    split_source <- substr(source, split_start, split_end + 2L)
    testthat::expect_match(split_source, "chunk_order = 1;", fixed = TRUE)
    testthat::expect_match(split_source, "drop analysis_order;", fixed = TRUE)
    for (marker in c(
      "data _TFL_HCIN_001_001;", "class analysis_order column_order node_key;",
      "output out=_TFL_HCRAW_001_001", "left join _TFL_STAT_003 as m1",
      "from _TFL_REND_003 as r left join _TFL_HDISP_001_001",
      "label = node_label; row_role = 'dynamic';", "row_role = 'static';"
    )) testthat::expect_true(grepl(marker, source, fixed = TRUE), info = marker)
    for (index in seq_len(count)) {
      suffix <- sprintf("%03d", index + 1L)
      for (marker in c(
        paste0("analysis_value = VALUE", index, ";"),
        paste0("data _TFL_CIN_", suffix, "_001 _TFL_CIN_", suffix, ";"),
        paste0("if analysis_order = ", index, " then output _TFL_CRAW_", suffix, ";"),
        paste0("from _TFL_KEY_", suffix, " as k left join _TFL_CRAW_", suffix),
        paste0("left join _TFL_CPREC_", suffix, " as p"),
        paste0("analysis_id = 'a", index, "';")
      )) testthat::expect_true(grepl(marker, source, fixed = TRUE), info = marker)
      testthat::expect_false(grepl(paste0("set _TFL_CIN_", suffix, "_001;"), source, fixed = TRUE))
    }
    testthat::expect_identical(generate_table_source(bundle, "t1")$source, source)
    compare <- generate_table_source(bundle, "t1", output_mode = "compare")
    testthat::expect_true(compare$passed)
    testthat::expect_equal(hierarchical_source_count(compare$source, "proc means"), 1L)
  }
})

testthat::test_that("shared MEANS keeps each counting-unit guard and precision before analysis", {
  for (unit in c("record", "distinct_subject", "distinct_key")) {
    result <- generate_table_source(hierarchical_continuous_group_fixture(unit = unit),
                                    "t1", include_duplicate_check = FALSE)
    testthat::expect_true(result$passed)
    source <- result$source
    means_position <- regexpr("proc means", source, fixed = TRUE)[[1L]]
    testthat::expect_equal(hierarchical_source_count(source, "proc means"), 1L)
    testthat::expect_false(grepl("duplicate_key", source, fixed = TRUE))
    testthat::expect_equal(hierarchical_source_count(source, "continuous_unit_multiple_values"),
                           if (unit == "record") 0L else 2L)
    for (suffix in c("002", "003")) {
      marker <- paste0("create table _TFL_CPREC_", suffix, " as")
      position <- regexpr(marker, source, fixed = TRUE)[[1L]]
      testthat::expect_true(position > 0L && position < means_position, info = marker)
      if (unit != "record") {
        marker <- paste0("data _TFL_CUNIT_", suffix, ";")
        position <- regexpr(marker, source, fixed = TRUE)[[1L]]
        testthat::expect_true(position > 0L && position < means_position, info = marker)
      }
    }
    if (unit == "distinct_key") {
      testthat::expect_equal(hierarchical_source_count(
        source, "by chunk_order column_order node_key USUBJID AESEQ;"), 2L)
    }
  }
})

testthat::test_that("compatible blocks share only value conversion and retain private result stages", {
  for (count in c(2L, 3L, 4L)) {
    bundle <- hierarchical_continuous_group_fixture(count)
    result <- generate_table_source(bundle, "t1")
    testthat::expect_true(result$passed)
    source <- result$source
    suffixes <- sprintf("%03d", seq_len(count) + 1L)
    conversion <- paste0("data ", paste0("_TFL_STAT_", suffixes, collapse = " "), ";")
    testthat::expect_true(grepl(conversion, source, fixed = TRUE))
    testthat::expect_equal(hierarchical_source_count(source, "select (statistic_id);"), 1L)
    testthat::expect_equal(hierarchical_source_count(source,
      "ERROR: [USER] Relative digits resolved to a negative value."), 1L)
    convert_position <- regexpr("select (statistic_id);", source, fixed = TRUE)[[1L]]
    last_join <- regexpr(paste0("create table _TFL_CJOIN_", tail(suffixes, 1L), " as"),
                        source, fixed = TRUE)[[1L]]
    first_render <- regexpr("proc sort data=_TFL_STAT_002", source, fixed = TRUE)[[1L]]
    testthat::expect_lt(last_join, convert_position)
    testthat::expect_lt(convert_position, first_render)
    for (suffix in suffixes) {
      for (marker in c(
        paste0("_TFL_CJOIN_", suffix, "(in=_tfl_result_", suffix, ")"),
        paste0("if _tfl_result_", suffix, " then output _TFL_STAT_", suffix, ";"),
        paste0("data _TFL_KEY_MAP_", suffix, ";"),
        paste0("create table _TFL_KEY_", suffix, " as"),
        paste0("create table _TFL_CJOIN_", suffix, " as"),
        paste0("proc sort data=_TFL_STAT_", suffix, " out=_TFL_RSTAT_", suffix, ";"),
        paste0("data _TFL_REND_", suffix, ";")
      )) testthat::expect_true(grepl(marker, source, fixed = TRUE), info = marker)
    }
    testthat::expect_equal(hierarchical_source_count(source,
      "by chunk_order node_key row_order column_order;"), count)
    testthat::expect_false(grepl("%macro|_TFL_HCSTAT_|_TFL_HCJOIN_|_TFL_HCKEY_", source))
    compare <- generate_table_source(bundle, "t1", output_mode = "compare")
    testthat::expect_equal(hierarchical_source_count(compare$source, "select (statistic_id);"), 1L)
  }
})

testthat::test_that("hierarchical continuous groups stop at every incompatible or intervening block", {
  for (boundary in c("unit", "level", "key_fields", "key_order", "categorical")) {
    bundle <- hierarchical_continuous_group_fixture(
      unit = if (grepl("key", boundary)) "distinct_key" else "record"
    )
    chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
    if (boundary == "unit") chunk$analysis_blocks[[2L]]$counting_unit <- "distinct_subject"
    if (boundary == "level") chunk$analysis_blocks[[2L]]$anchor_level <- "l2"
    if (boundary == "key_fields") chunk$analysis_blocks[[2L]]$distinct_key <- c("USUBJID", "VISIT")
    if (boundary == "key_order") chunk$analysis_blocks[[2L]]$distinct_key <- c("AESEQ", "USUBJID")
    if (boundary == "categorical") {
      categorical <- list(
        id = "category", anchor_level = "l1", placement = "below",
        type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
        denominator = list(scope = "current_group", unit = "distinct_subject"),
        rows = list(list(id = "r", type = "analysis", label = "Any", condition = "1",
                         statistics = list(list(id = "n")), cell_format = "{n}"))
      )
      chunk$analysis_blocks <- append(chunk$analysis_blocks, list(categorical), after = 1L)
    }
    bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
    result <- generate_table_source(bundle, "t1")
    testthat::expect_true(result$passed, info = boundary)
    testthat::expect_equal(hierarchical_source_count(result$source, "proc means"), 2L, info = boundary)
    testthat::expect_false(grepl("_TFL_HCIN_", result$source, fixed = TRUE), info = boundary)
    testthat::expect_false(grepl("in=_tfl_result_", result$source, fixed = TRUE), info = boundary)
  }
})

testthat::test_that("group member positions and reserved namespaces survive boundaries and containers", {
  bundle <- hierarchical_continuous_group_fixture(3L)
  first <- bundle$templates[[1L]]$body$chunks[[1L]]
  first$analysis_blocks[[1L]]$anchor_level <- "l2"
  second <- first
  second$id <- "hier2"
  bundle$templates[[1L]]$body$chunks <- list(first, second)
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_equal(hierarchical_source_count(result$source, "proc means"), 4L)
  for (marker in c("data _TFL_HCIN_001_002;", "data _TFL_HCIN_002_002;",
                   "data _TFL_CRAW_004 _TFL_CRAW_005;",
                   "data _TFL_CRAW_007 _TFL_CRAW_008;",
                   "if analysis_order = 2 then output _TFL_CRAW_004;",
                   "if analysis_order = 3 then output _TFL_CRAW_005;",
                   "if analysis_order = 2 then output _TFL_CRAW_007;",
                   "if analysis_order = 3 then output _TFL_CRAW_008;",
                   "data _TFL_STAT_004 _TFL_STAT_005;",
                   "data _TFL_STAT_007 _TFL_STAT_008;",
                   "if _tfl_result_004 then output _TFL_STAT_004;",
                   "if _tfl_result_008 then output _TFL_STAT_008;")) {
    testthat::expect_true(grepl(marker, result$source, fixed = TRUE), info = marker)
  }
})

testthat::test_that("registered alternative continuous emitters keep control of their source", {
  registry <- default_chunk_registry()
  calls <- 0L
  registry$definitions$continuous_summary$emitter <- function(plan, resolved) {
    calls <<- calls + 1L
    continuous_summary_emitter(plan, resolved)
  }
  result <- generate_table_source(hierarchical_continuous_group_fixture(), "t1", registry = registry)
  testthat::expect_true(result$passed)
  testthat::expect_equal(calls, 2L)
  testthat::expect_equal(hierarchical_source_count(result$source, "proc means"), 2L)
  testthat::expect_false(grepl("in=_tfl_result_", result$source, fixed = TRUE))
})

testthat::test_that("hierarchical report rows include nodes, below rows, and level boundaries", {
  result <- generate_table_source(hierarchical_report_fixture(), "t1")
  testthat::expect_true(result$passed)
  source <- result$source
  for (marker in c(
    "Discover hierarchical level 1 nodes", "Discover hierarchical level 2 nodes",
    "if missing(SOC) then delete;", "if missing(PT) then delete;",
    "data _TFL_HLEVEL_001_001 _TFL_HNODES_001_001",
    "data _TFL_HLEVEL_001_002 _TFL_HNODES_001_002",
    "level_component = cats(lengthn", "group_path = catt(parent_node_key, level_component);",
    "WARNING: [USER] duplicate_key", "class chunk_order column_order node_key;",
    "from _TFL_HMEM_001 as m inner join", "on m.USUBJID = s._TFL_SOURCE_SUBJECT;",
    "data _TFL_HLABEL_001_001;", "data _TFL_HLABEL_001_002;",
    "row_role = 'static';", "analysis_id = 'a1';",
    "order_key = cats(node_order_path, 'A');",
    "order_key = cats(display_order_path, 'B', put(block_order, z10.), put(row_order, z10.));",
    "node_order_path = cats(display_parent_path, 'C', put(sibling_order, z10.));",
    "by order_key column_order;", "if first.order_key then row_sequence + 1;",
    "hierarchy_level ne previous_level", "proc report data=WORK._TFL_ASM_001"
  )) testthat::expect_true(grepl(marker, source, fixed = TRUE), info = marker)
  testthat::expect_equal(length(regmatches(source, gregexpr("if not (SAFFL = 'Y') then delete;", source, fixed = TRUE))[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(source, gregexpr("proc means", source, fixed = TRUE))[[1L]]), 1L)
})

testthat::test_that("same-row analysis uses dynamic node labels without duplicate label rows", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$node_role <- "analysis"
  chunk$levels[[1L]]$node_analysis_id <- "a1"
  chunk$analysis_blocks[[1L]]$placement <- "same_row"
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_false(grepl("data _TFL_HLABEL_001_001;", result$source, fixed = TRUE))
  testthat::expect_true(grepl("label = node_label; row_role = 'dynamic';", result$source, fixed = TRUE))
  testthat::expect_true(grepl("order_key = cats(display_order_path, 'A');", result$source, fixed = TRUE))
})

testthat::test_that("duplicate checking is optional for hierarchical record sources", {
  bundle <- hierarchical_report_fixture()
  checked <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  unchecked <- generate_table_source(bundle, "t1", include_duplicate_check = FALSE)
  testthat::expect_true(checked$passed)
  testthat::expect_true(unchecked$passed)
  testthat::expect_match(checked$source, "by USUBJID AESEQ;", fixed = TRUE)
  testthat::expect_match(checked$source, "WARNING: [USER] duplicate_key", fixed = TRUE)
  testthat::expect_false(grepl("_TFL_GUARD_|duplicate_key", unchecked$source))
  testthat::expect_match(unchecked$source, "Discover hierarchical level 2 nodes", fixed = TRUE)
  testthat::expect_match(unchecked$source, "Execute nested primitive analysis", fixed = TRUE)
})

testthat::test_that("nested key maps cross join the shared header catalog and scoped nodes", {
  bundle <- hierarchical_report_fixture()
  bundle$headers[[1L]]$columns[[2L]] <- list(
    id = "empty", label = "Empty", condition = "0", display_order = 2L,
    width = 1, alignment = "center"
  )
  resolved <- resolve_generation_request(new_generation_request(bundle, "t1"))$value
  parent <- plan_primitive_batches(resolved)$value[[1L]]
  block <- parent$chunks[[1L]]$analysis_blocks[[1L]]
  nested <- hierarchical_nested_plan(parent, block, 1L, resolved)
  testthat::expect_identical(nested$header_columns_dataset, "_TFL_HCOLS_001")
  fragment <- paste(expected_cell_skeleton_source(nested), collapse = "\n")
  testthat::expect_match(fragment, "cross join _TFL_HCOLS_001 as h", fixed = TRUE)
  testthat::expect_match(fragment, "cross join _TFL_HNODES_001_001 as n", fixed = TRUE)
  testthat::expect_match(fragment, "n.node_key, n.group_path, n.node_label", fixed = TRUE)
  testthat::expect_match(fragment, "m.statistic_order, n.node_order_path;", fixed = TRUE)
  lines <- strsplit(fragment, "\n", fixed = TRUE)[[1L]]
  records <- lines[seq.int(match("  datalines;", lines) + 1L, match(";", lines) - 1L)]
  testthat::expect_length(records, 1L)
  testthat::expect_false(any(grepl('"all"|"empty"', records)))

  nested$header_columns_dataset <- "_TFL_CUSTOM_COLUMNS"
  fragment <- paste(expected_cell_skeleton_source(nested), collapse = "\n")
  testthat::expect_match(fragment, "cross join _TFL_CUSTOM_COLUMNS as h", fixed = TRUE)
})

testthat::test_that("nested batches have unique namespaces and result sorting uses raw statistics", {
  bundle <- hierarchical_report_fixture()
  first <- bundle$templates[[1L]]$body$chunks[[1L]]
  first$levels[[1L]]$result_sort <- list(
    metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
    column_order = c(1L, 0L), direction = "desc"
  )
  second <- first
  second$id <- "hier2"
  bundle$templates[[1L]]$body$chunks <- list(first, second)
  resolved <- resolve_generation_request(new_generation_request(bundle, "t1"))$value
  plans <- plan_primitive_batches(resolved)$value
  nested <- lapply(plans, function(plan) hierarchical_nested_plan(plan, plan$chunks[[1L]]$analysis_blocks[[1L]], 1L, resolved))
  testthat::expect_identical(vapply(nested, function(plan) plan$batch_order, integer(1L)), c(3L, 4L))
  testthat::expect_length(unique(vapply(nested, function(plan) plan$render_dataset, "")), 2L)
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  for (marker in c("m1.value else . end as metric_1", "metric_missing_1 descending metric_1 label_sort",
                   "data _TFL_HLABEL_001_001;", "data _TFL_HLABEL_002_001;",
                   "set _TFL_REND_001 _TFL_REND_002;")) {
    testthat::expect_true(grepl(marker, result$source, fixed = TRUE), info = marker)
  }
})

testthat::test_that("hierarchical continuous blocks implement all counting-unit semantics", {
  record_bundle <- hierarchical_report_fixture()
  record_source <- generate_table_source(record_bundle, "t1")
  testthat::expect_true(record_source$passed)
  testthat::expect_false(grepl("_TFL_CUNIT_", record_source$source, fixed = TRUE))
  testthat::expect_match(record_source$source,
    "data _TFL_CIN_002_001 _TFL_CIN_002;", fixed = TRUE)
  testthat::expect_false(grepl("set _TFL_CIN_002_001;", record_source$source, fixed = TRUE))
  testthat::expect_match(record_source$source, "proc means data=_TFL_CIN_002 nway noprint;",
                         fixed = TRUE)

  subject_bundle <- hierarchical_report_fixture()
  subject_bundle$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]]$counting_unit <-
    "distinct_subject"
  subject_source <- generate_table_source(subject_bundle, "t1")
  testthat::expect_true(subject_source$passed)
  for (marker in c(
    "keep chunk_order column_order analysis_value source_row node_key USUBJID;",
    "by chunk_order column_order node_key USUBJID source_row;",
    "by chunk_order column_order node_key USUBJID;",
    "if first.USUBJID then do;", "if last.USUBJID then do;",
    "counting_unit=distinct_subject", "continuous_unit_multiple_values",
    "abort cancel;", "proc means data=_TFL_CUNIT_002 nway noprint;"
  )) testthat::expect_match(subject_source$source, marker, fixed = TRUE)

  key_bundle <- hierarchical_report_fixture()
  block <- key_bundle$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]]
  block$counting_unit <- "distinct_key"
  block$distinct_key <- c("USUBJID", "AESEQ")
  key_bundle$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]] <- block
  key_source <- generate_table_source(key_bundle, "t1")
  testthat::expect_true(key_source$passed)
  for (marker in c(
    "keep chunk_order column_order analysis_value source_row node_key USUBJID AESEQ;",
    "by chunk_order column_order node_key USUBJID AESEQ source_row;",
    "by chunk_order column_order node_key USUBJID AESEQ;",
    "if first.AESEQ then do;", "if last.AESEQ then do;",
    "counting_unit=distinct_key", "' USUBJID=' USUBJID", "' AESEQ=' AESEQ",
    "proc means data=_TFL_CUNIT_002 nway noprint;"
  )) testthat::expect_match(key_source$source, marker, fixed = TRUE)
})

testthat::test_that("hierarchical blocks anchored at one level share one membership expansion", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  chunk$analysis_blocks[[2L]] <- list(
    id = "a2", anchor_level = "l1", placement = "below",
    type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
    denominator = list(scope = "current_group", unit = "distinct_subject"),
    rows = list(list(
      id = "r2", type = "analysis", label = "Any record", condition = "1",
      statistics = list(list(id = "n")), cell_format = "{n}"
    ))
  )
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk

  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  source <- result$source
  testthat::expect_equal(length(regmatches(
    source, gregexpr("create table _TFL_HMERGE_001_001 as", source, fixed = TRUE)
  )[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(
    source, gregexpr("from _TFL_HMEM_001 as m inner join", source, fixed = TRUE)
  )[[1L]]), 1L)
  testthat::expect_match(source,
    "data _TFL_CMERGE_002_001;\n  set _TFL_HMERGE_001_001;", fixed = TRUE)
  testthat::expect_match(source,
    "data _TFL_KMERGE_003_001;\n  set _TFL_HMERGE_001_001;", fixed = TRUE)
  testthat::expect_match(source,
    "if (1) then do; row_order = 1; output; end;", fixed = TRUE)
  testthat::expect_equal(length(regmatches(
    source, gregexpr("source_row = _n_;", source, fixed = TRUE)
  )[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(
    source, gregexpr("proc means", source, fixed = TRUE)
  )[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(
    source, gregexpr("proc freq", source, fixed = TRUE)
  )[[1L]]), 1L)
})

testthat::test_that("hierarchical membership expansion remains isolated by anchor level", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  second <- chunk$analysis_blocks[[1L]]
  second$id <- "a2"
  second$anchor_level <- "l2"
  chunk$analysis_blocks[[2L]] <- second
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk

  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "create table _TFL_HMERGE_001_001 as", fixed = TRUE)
  testthat::expect_match(result$source, "create table _TFL_HMERGE_001_002 as", fixed = TRUE)
  testthat::expect_match(result$source,
    "data _TFL_CMERGE_002_001;\n  set _TFL_HMERGE_001_001;", fixed = TRUE)
  testthat::expect_match(result$source,
    "data _TFL_CMERGE_003_001;\n  set _TFL_HMERGE_001_002;", fixed = TRUE)
})
