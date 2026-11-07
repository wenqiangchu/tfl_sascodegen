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
    expected_means <- if (identical(boundary, "categorical")) 3L else 2L
    testthat::expect_equal(hierarchical_source_count(result$source, "proc means"), expected_means,
                           info = boundary)
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
    # record counting has no meaningful key, so no duplicate_key guard is emitted
    "class chunk_order column_order node_key;",
    "from _TFL_HMEM_001 as m inner join", "on m.USUBJID = s._TFL_SOURCE_SUBJECT;",
    "data _TFL_HLABEL_001_001;", "data _TFL_HLABEL_001_002;",
    "row_role = 'static';", "analysis_id = 'a1';",
    "order_key = cats(node_order_path, 'A');",
    "order_key = cats(display_order_path, 'B', put(block_order, z10.), put(row_order, z10.));",
    "node_order_path = cats(display_parent_path, 'C', put(sibling_order, z10.));",
    "by order_key column_order;", "if first.order_key then row_sequence + 1;",
    "(hierarchy_level = 1 and row_role ne 'static') or", "proc report data=WORK._TFL_PAGED_001"
  )) testthat::expect_true(grepl(marker, source, fixed = TRUE), info = marker)
  testthat::expect_equal(length(regmatches(source, gregexpr("if not (SAFFL = 'Y') then delete;", source, fixed = TRUE))[[1L]]), 1L)
  testthat::expect_equal(length(regmatches(source, gregexpr("proc means", source, fixed = TRUE))[[1L]]), 1L)
})

testthat::test_that("format levels generate complete parent-scoped node catalogs", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$format <- "visit_fmt"
  chunk$levels[[1L]]$order_variable <- NULL
  chunk$levels[[1L]]$order_direction <- NULL
  chunk$levels[[2L]]$format <- "$category_fmt"
  chunk$levels[[2L]]$order_variable <- NULL
  chunk$levels[[2L]]$order_direction <- NULL
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk

  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  source <- result$source
  testthat::expect_match(source, "data _TFL_HFMTIN_001_001;", fixed = TRUE)
  testthat::expect_match(source,
                         "class parent_node_key SOC / preloadfmt order=data missing;",
                         fixed = TRUE)
  testthat::expect_match(source, "format SOC visit_fmt.;", fixed = TRUE)
  testthat::expect_match(source, "data _TFL_HFMTIN_001_002;", fixed = TRUE)
  testthat::expect_match(source,
                         "_TFL_HNODES_001_001(rename=(node_key=_tfl_parent_key) in=_tfl_parent);",
                         fixed = TRUE)
  testthat::expect_match(source, "format PT $category_fmt.;", fixed = TRUE)
  testthat::expect_match(source, "nway completetypes noprint", fixed = TRUE)
  testthat::expect_match(source, "flag = 1;", fixed = TRUE)
})

testthat::test_that("formatted hierarchy text bounds use compiled format widths before node discovery", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$variable <- "AVISITN"
  chunk$levels[[1L]]$format <- "visit_fmt"
  chunk$levels[[1L]]$order_variable <- NULL
  chunk$levels[[1L]]$order_direction <- NULL
  # label_variable cannot be combined with format (rejected at the model layer),
  # so the sizing probe must never consult it.
  chunk$levels[[2L]]$format <- "$category_fmt"
  chunk$levels[[2L]]$order_variable <- NULL
  chunk$levels[[2L]]$order_direction <- NULL
  chunk$levels[[2L]]$missing_policy <- "label"
  chunk$levels[[2L]]$missing_label <- strrep("M", 700L)
  plan <- list(batch_order = 1L, chunks = list(chunk))
  sizing <- paste(hierarchical_text_lengths_source(plan), collapse = "\n")
  testthat::expect_match(sizing,
    "if 0 then set _TFL_HSRC_001(keep=AVISITN PT);", fixed = TRUE)
  testthat::expect_match(sizing,
    "if 0 then _tfl_fmt_value_001 = put(AVISITN, visit_fmt.);", fixed = TRUE)
  testthat::expect_match(sizing,
    "if 0 then _tfl_fmt_value_002 = put(PT, $category_fmt.);", fixed = TRUE)
  testthat::expect_match(sizing,
    "_tfl_value_length = max(vlength(_tfl_fmt_value_002), 700) + 2;", fixed = TRUE)
  testthat::expect_match(sizing, "_tfl_key_length + _tfl_value_length + 32;", fixed = TRUE)
  testthat::expect_match(sizing,
    "_tfl_label_length = max(_tfl_label_length, _tfl_value_length - 2);", fixed = TRUE)
  testthat::expect_false(grepl("IGNORED_LABEL", sizing, fixed = TRUE))
  # The descriptor-only probe also runs on an empty source; no SET consumes a row.
  testthat::expect_false(grepl("(?m)^\\s*set ", sizing, perl = TRUE))
  # A never-executed SET cannot reach EOF; explicitly stop after publishing widths.
  testthat::expect_match(sizing, "  stop;\nrun;", fixed = TRUE)
  testthat::expect_false(grepl("(?m)^\\s*_tfl_(key|label)_length = 32767;", sizing, perl = TRUE))
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  testthat::expect_lt(regexpr(sizing, result$source, fixed = TRUE)[[1L]],
                      regexpr("data _TFL_HFMTIN_001_001;", result$source, fixed = TRUE)[[1L]])

  # Each level has its own probe, even when two formats use the same raw variable.
  chunk$levels[[2L]]$variable <- "AVISITN"
  chunk$levels[[2L]]$format <- "visit_group_fmt"
  plan$chunks <- list(chunk)
  sizing <- paste(hierarchical_text_lengths_source(plan), collapse = "\n")
  testthat::expect_match(sizing, "keep=AVISITN);", fixed = TRUE)
  testthat::expect_match(sizing,
    "_tfl_fmt_value_002 = put(AVISITN, visit_group_fmt.);", fixed = TRUE)
  plain <- hierarchical_report_fixture()$templates[[1L]]$body$chunks[[1L]]
  plan$chunks <- list(plain)
  testthat::expect_false(grepl("_tfl_fmt_value_", paste(hierarchical_text_lengths_source(plan),
                                                    collapse = "\n"), fixed = TRUE))
})

testthat::test_that("empty formatted roots seed only the catalog and joins retain format order", {
  chunk <- hierarchical_report_fixture()$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$format <- "$soc_fmt"
  chunk$levels[[2L]]$format <- "$pt_fmt"
  plan <- list(batch_order = 1L, chunks = list(chunk))
  root <- paste(hierarchical_formatted_level_source(plan, 1L), collapse = "\n")
  testthat::expect_match(root,
    "if _n_ = 1 then do;\n    call missing(SOC);\n    flag = .; output;\n  end;", fixed = TRUE)
  # The seed writes a missing value before SET defines the variable, so the type
  # has to be declared. Without it SAS creates a numeric SOC and the character
  # format then fails with "already defined as character and numeric" -- which is
  # exactly what a first level driven by a character format hits.
  testthat::expect_match(root, "length SOC $", fixed = TRUE)
  testthat::expect_lt(regexpr("length SOC $", root, fixed = TRUE)[[1L]],
                      regexpr("call missing(SOC);", root, fixed = TRUE)[[1L]])
  # A numeric format must not get a character declaration: CALL MISSING already
  # picks the numeric type, and the `$` in `$soc_fmt` is what separates the two.
  chunk$levels[[1L]]$format <- "num_fmt"
  plan$chunks[[1L]] <- chunk
  numeric_root <- paste(hierarchical_formatted_level_source(plan, 1L), collapse = "
")
  testthat::expect_false(grepl("length SOC $", numeric_root, fixed = TRUE))
  testthat::expect_lt(regexpr("flag = .; output;", root, fixed = TRUE)[[1L]],
                      regexpr("set _TFL_HNODE_001(keep=SOC);", root, fixed = TRUE)[[1L]])
  observed_section <- strsplit(root, "data _TFL_HFOBS_001_001;", fixed = TRUE)[[1L]][[2L]]
  testthat::expect_match(observed_section, "set _TFL_HNODE_001;", fixed = TRUE)
  testthat::expect_false(grepl("flag = .; output;", observed_section, fixed = TRUE))
  child <- paste(hierarchical_formatted_level_source(plan, 2L), collapse = "\n")
  testthat::expect_match(child,
    "set _TFL_HFMTRAW_001_002;\n  _tfl_format_order = _n_;", fixed = TRUE)
  testthat::expect_match(child, "order by c._tfl_format_order;", fixed = TRUE)
  testthat::expect_match(child, "by parent_node_key _tfl_format_order;", fixed = TRUE)
})

testthat::test_that("every internal sort key is created in the level that sorts by it", {
  chunk <- hierarchical_report_fixture()$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$format <- "$soc_fmt"
  chunk$levels[[2L]]$format <- "$pt_fmt"
  plan <- list(batch_order = 1L, chunks = list(chunk))
  sort_blocks <- 0L
  for (level_order in seq_along(chunk$levels)) {
    text <- paste(hierarchical_formatted_level_source(plan, level_order), collapse = "\n")
    matches <- gregexpr("proc sort[^;]*;[[:space:]]*by [^;]*;", text)
    blocks <- regmatches(text, matches)[[1L]]
    starts <- matches[[1L]]
    for (index in seq_along(blocks)) {
      sort_blocks <- sort_blocks + 1L
      keys <- regmatches(blocks[[index]], gregexpr("(?<= by )[^;]*", blocks[[index]], perl = TRUE))[[1L]]
      keys <- Filter(nzchar, strsplit(trimws(keys), "[[:space:]]+")[[1L]])
      prefix <- substr(text, 1L, starts[[index]])
      for (key in keys) {
        if (!startsWith(key, "_tfl_")) next
        # A sort key that is only referenced (never created) fails in SAS with
        # "Variable ... is not on file", so require an assignment of its own.
        testthat::expect_gt(
          regexpr(paste0(key, " = "), prefix, fixed = TRUE)[[1L]], 0L,
          label = paste0(key, " is sorted by at level ", level_order, " but never assigned")
        )
      }
    }
  }
  testthat::expect_gt(sort_blocks, 0L)
})

testthat::test_that("catalog and analysis labels strip VVALUE padding identically", {
  chunk <- hierarchical_report_fixture()$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$format <- "$soc_fmt"
  chunk$levels[[2L]]$format <- "$pt_fmt"
  plan <- list(batch_order = 1L, chunks = list(chunk))
  for (level_order in seq_along(chunk$levels)) {
    text <- paste(hierarchical_formatted_level_source(plan, level_order), collapse = "\n")
    variable <- chunk$levels[[level_order]]$variable
    testthat::expect_equal(
      lengths(regmatches(text, gregexpr(paste0("node_label = strip(vvalue(", variable, "));"),
                                       text, fixed = TRUE)))[[1L]], 2L,
      label = paste0("both label paths for level ", level_order, " must strip padding")
    )
    testthat::expect_false(
      grepl(paste0("node_label = vvalue(", variable, ");"), text, fixed = TRUE),
      label = paste0("level ", level_order, " must not emit an unstripped label")
    )
  }
})

testthat::test_that("formatted levels replace inherited ordering before another child consumes it", {
  bundle <- hierarchical_report_fixture()
  chunk <- bundle$templates[[1L]]$body$chunks[[1L]]
  chunk$levels[[1L]]$format <- "$soc_fmt"
  chunk$levels[[1L]]$order_variable <- NULL
  chunk$levels[[1L]]$order_direction <- NULL
  chunk$levels[[2L]]$format <- "$pt_fmt"
  chunk$levels[[2L]]$order_variable <- NULL
  chunk$levels[[2L]]$order_direction <- NULL
  # Level 3 stays unformatted on purpose: the test asserts that a formatted
  # level's ordering is not inherited by a following non-format level.
  chunk$levels[[3L]] <- list(id = "l3", variable = "SEV", order_variable = "SEVN",
                            order_direction = "asc", node_role = "label",
                            missing_policy = "exclude")
  bundle$templates[[1L]]$body$chunks[[1L]] <- chunk
  result <- generate_table_source(bundle, "t1")
  testthat::expect_true(result$passed)
  step <- function(dataset) {
    match <- regmatches(result$source, regexec(paste0("(?s)data ", dataset,
      ";\\n(.*?)\\nrun;"), result$source, perl = TRUE))[[1L]]
    testthat::expect_length(match, 2L)
    match[[2L]]
  }
  testthat::expect_false(grepl("drop node_order_path;", step("_TFL_HFOBS_001_001"), fixed = TRUE))
  testthat::expect_match(step("_TFL_HFOBS_001_002"), "drop node_order_path;", fixed = TRUE)
  testthat::expect_match(result$source,
    "select o.*, n.node_order_path from _TFL_HFOBS_001_002 as o left join _TFL_HNODES_001_002 as n",
    fixed = TRUE)
  child <- step("_TFL_HVALUE_001_003")
  testthat::expect_match(child, "set _TFL_HLEVEL_001_002;", fixed = TRUE)
  testthat::expect_match(child, "parent_order_path = node_order_path;", fixed = TRUE)
})

testthat::test_that("formatted missing labels require real records rather than parent seeds", {
  for (policy in c("label", "exclude", "error")) {
    bundle <- hierarchical_report_fixture()
    level <- bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]]
    level$format <- "$category_fmt"
    # A formatted level takes its order from the format, not from these fields.
    level$order_variable <- NULL
    level$order_direction <- NULL
    level$missing_policy <- policy
    if (policy == "label") level$missing_label <- "Missing"
    bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]] <- level
    result <- generate_table_source(bundle, "t1")
    testthat::expect_true(result$passed)
    step <- function(dataset) {
      match <- regmatches(result$source,
        regexec(paste0("(?s)data ", dataset, ";\\n(.*?)\\nrun;"),
                result$source, perl = TRUE))[[1L]]
      testthat::expect_length(match, 2L)
      match[[2L]]
    }
    input <- step("_TFL_HFMTIN_001_002")
    testthat::expect_match(input, "parent_node_key = _tfl_parent_key;", fixed = TRUE)
    testthat::expect_match(input, "call missing(PT);\n    flag = .;", fixed = TRUE)
    testthat::expect_match(input, "parent_node_key = node_key; flag = 1;", fixed = TRUE)
    catalog <- step("_TFL_HFCATS_001_002")
    if (policy == "label") {
      # Ordinary zero-frequency format classes survive; only unobserved missing is removed.
      testthat::expect_match(catalog, "if missing(PT) and _tfl_n = 0 then delete;", fixed = TRUE)
      testthat::expect_match(catalog, "if missing(PT) then node_label = 'Missing';", fixed = TRUE)
      testthat::expect_false(grepl("if _tfl_n = 0 then delete;", catalog, fixed = TRUE))
    } else {
      testthat::expect_match(catalog, "if missing(PT) then delete;", fixed = TRUE)
    }
    # Seeds are catalog-only: actual level membership is assigned from real records.
    observed <- step("_TFL_HFOBS_001_002")
    testthat::expect_match(observed, "set _TFL_HLEVEL_001_001;", fixed = TRUE)
    testthat::expect_false(grepl("_tfl_parent|_TFL_HFMTIN", observed))
  }
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
  # The fixture block counts records, whose key is source_row. A per-block check
  # on that key could never fire, so record counting emits no guard at all.
  checked <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  unchecked <- generate_table_source(bundle, "t1", include_duplicate_check = FALSE)
  testthat::expect_true(checked$passed)
  testthat::expect_true(unchecked$passed)
  testthat::expect_false(grepl("_TFL_GUARD_|duplicate_key", checked$source))
  testthat::expect_false(grepl("_TFL_GUARD_|duplicate_key", unchecked$source))
  testthat::expect_match(unchecked$source, "Discover hierarchical level 2 nodes", fixed = TRUE)
  testthat::expect_match(unchecked$source, "Execute nested primitive analysis", fixed = TRUE)
})

testthat::test_that("distinct-subject blocks check duplicates on the counting key", {
  bundle <- hierarchical_report_fixture()
  bundle$templates[[1L]]$body$chunks[[1L]]$analysis_blocks[[1L]]$counting_unit <-
    "distinct_subject"
  checked <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  testthat::expect_true(checked$passed)
  # The guard reuses the counting-unit key but drops column_order, otherwise the
  # header expansion would report the same source duplicate once per column.
  testthat::expect_match(checked$source, "by chunk_order node_key USUBJID;", fixed = TRUE)
  testthat::expect_match(checked$source, "WARNING: [USER] duplicate_key", fixed = TRUE)
  guard_lines <- grep("_TFL_GUARD_", strsplit(checked$source, "
", fixed = TRUE)[[1]],
                       value = TRUE)
  testthat::expect_false(grepl("column_order", paste(guard_lines, collapse = "
"),
                               fixed = TRUE))
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
    "WARNING: [USER] continuous_unit_multiple_values",
    "proc means data=_TFL_CUNIT_002 nway noprint;"
  )) testthat::expect_match(subject_source$source, marker, fixed = TRUE)
  # Multiple values for one counting unit are reported but no longer abort the run.
  testthat::expect_false(grepl("abort cancel", subject_source$source, fixed = TRUE))

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
  )[[1L]]), 2L)
  testthat::expect_equal(length(regmatches(
    source, gregexpr("proc means", source, fixed = TRUE)
  )[[1L]]), 2L)
})

testthat::test_that("hierarchical sibling counters do not propagate to descendant input", {
  result <- generate_table_source(hierarchical_report_fixture(), "t1")
  testthat::expect_true(result$passed)
  for (level in c("001", "002")) {
    testthat::expect_match(result$source,
      paste0("  drop sibling_order;\n  output _TFL_HLEVEL_001_", level, ";"), fixed = TRUE)
  }
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
