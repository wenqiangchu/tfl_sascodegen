# Source emitter for categorical counting events and complete display cells.

categorical_source_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KSRC_%03d_%03d", batch_order, chunk_order)
}

categorical_merged_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KMERGE_%03d_%03d", batch_order, chunk_order)
}

categorical_chunk_input_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KIN_%03d_%03d", batch_order, chunk_order)
}

categorical_chunk_pre_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KPRE_%03d_%03d", batch_order, chunk_order)
}

categorical_chunk_key_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KKEY_%03d_%03d", batch_order, chunk_order)
}

categorical_combined_pre_dataset <- function(batch_order) {
  sprintf("_TFL_KPRE_%03d", batch_order)
}

categorical_batch_chunks_dataset <- function(batch_order) {
  sprintf("_TFL_KCHUNKS_%03d", batch_order)
}

categorical_batch_merged_dataset <- function(batch_order) {
  sprintf("_TFL_KMERGE_%03d", batch_order)
}

categorical_chunk_source <- function(plan, entry) {
  chunk <- entry$chunk
  source_dataset <- categorical_source_dataset(plan$batch_order, entry$chunk_order)
  merged_dataset <- categorical_merged_dataset(plan$batch_order, entry$chunk_order)
  input_dataset <- categorical_chunk_input_dataset(plan$batch_order, entry$chunk_order)
  denominator <- chunk$denominator
  eligibility <- switch(denominator$type,
    header_population = if ((denominator$unit %||% "distinct_subject") == "distinct_subject") "1" else "not missing(source_row)",
    non_missing = paste0("not missing(source_row) and not missing(", denominator$variable, ")"),
    custom = paste0("not missing(source_row) and (", denominator$expression, ")")
  )
  numerator_keys <- primitive_counting_keys(chunk)
  denominator_keys <- primitive_counting_keys(chunk, denominator$unit %||% "distinct_subject")
  pre_dataset <- categorical_chunk_pre_dataset(plan$batch_order, entry$chunk_order)
  row_output <- if (is.null(plan$nodes_dataset)) paste0("output ", pre_dataset, ";") else "output;"
  row_lines <- unlist(lapply(seq_along(chunk$rows), function(row_order) {
    row <- chunk$rows[[row_order]]
    if (!identical(row$type, "analysis")) return(character())
    paste0("    if (", row$condition, ") then do; row_order = ", row_order,
           "; ", row_output, " end;")
  }), use.names = FALSE)
  if (!is.null(plan$nodes_dataset)) return(paste(c(
    primitive_source_input(plan, entry, source_dataset, merged_dataset, "categorical"),
    "/* Normalize denominator and numerator counting events. */",
    paste0("data ", input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", merged_dataset, ";"),
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    paste0("  denominator_eligible = ", eligibility, ";"),
    "  if denominator_eligible then do; row_order = 0; output; end;",
    "  if not missing(source_row) then do;",
    row_lines,
    "  end;",
    paste0("  keep chunk_order row_order column_order node_key ",
           paste(unique(c(numerator_keys, denominator_keys)), collapse = " "), ";"),
    "run;"
  ), collapse = "\n"))
  key_dataset <- categorical_chunk_key_dataset(plan$batch_order, entry$chunk_order)
  source_dataset <- categorical_source_dataset(plan$batch_order, entry$chunk_order)
  # Deduplication needs the filtered source before counting events are emitted, so
  # the filter and the event projection are split when the option is enabled.
  dedup <- if (isTRUE(plan$auto_dedup)) {
    source_auto_dedup_guard(
      source_dataset, plan$subject_key %||% "USUBJID",
      sprintf("K%03d_%03d", plan$batch_order, entry$chunk_order)
    )
  } else {
    list(source = character(), dataset = chunk$source_data)
  }
  paste(c(
    "/* Filter categorical chunk source before merge. */",
    if (isTRUE(plan$auto_dedup)) c(
      paste0("data ", source_dataset, ";"),
      paste0("  set ", chunk$source_data, ";"),
      if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;"),
      "run;",
      dedup$source
    ) else character(),
    "/* Filter once and emit categorical source keys and counting events. */",
    paste0("data ", key_dataset, " ", pre_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    if (isTRUE(plan$auto_dedup)) {
      paste0("  set ", dedup$dataset, ";")
    } else {
      paste0("  set ", chunk$source_data, ";")
    },
    if (!isTRUE(plan$auto_dedup) && !is.null(chunk$filter)) {
      paste0("  if not (", chunk$filter, ") then delete;")
    } else character(),
    "  source_row = _n_;",
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    paste0("  output ", key_dataset, ";"),
    paste0("  denominator_eligible = ", eligibility, ";"),
    paste0("  if denominator_eligible then do; row_order = 0; output ", pre_dataset, "; end;"),
    "  if not missing(source_row) then do;",
    row_lines,
    "  end;",
    paste0("  keep ", paste(unique(c("chunk_order", "USUBJID", "source_row", "row_order",
                                      "node_key", "denominator_eligible", numerator_keys,
                                      denominator_keys)), collapse = " "), ";"),
    "run;"
  ), collapse = "\n")
}

categorical_batch_source_input <- function(plan) {
  suffix <- sprintf("%03d", plan$batch_order)
  pre <- categorical_combined_pre_dataset(plan$batch_order)
  chunks <- categorical_batch_chunks_dataset(plan$batch_order)
  merged <- categorical_batch_merged_dataset(plan$batch_order)
  input_names <- vapply(plan$chunk_orders, function(order) {
    categorical_chunk_pre_dataset(plan$batch_order, order)
  }, character(1L))
  key_names <- vapply(plan$chunk_orders, function(order) {
    categorical_chunk_key_dataset(plan$batch_order, order)
  }, character(1L))
  header_orders <- vapply(seq_along(plan$chunks), function(index) {
    if (identical(plan$chunks[[index]]$denominator$type, "header_population")) {
      plan$chunk_orders[[index]]
    } else NA_integer_
  }, integer(1L))
  header_orders <- header_orders[!is.na(header_orders)]
  scaffold <- if (length(header_orders)) c(
    "  union all",
    "  select b.chunk_order, m.USUBJID, m.header_column_id, m.column_order,",
    "         . as source_row, 0 as row_order, '' as node_key, 1 as denominator_eligible",
    paste0("  from ", chunks, " as b cross join ", plan$membership_dataset, " as m"),
    paste0("  where b.chunk_order in (", paste(header_orders, collapse = ", "), ")")
  ) else character()
  c(
    "/* Combine normalized categorical events before one membership merge. */",
    paste0("data ", pre, ";"),
    paste0("  set ", paste(input_names, collapse = " "), ";"),
    "run;",
    if (isTRUE(plan$include_duplicate_check)) c(
      "/* Check filtered categorical source keys once for this batch. */",
      paste0("data _TFL_KKEY_", suffix, ";"),
      paste0("  set ", paste(key_names, collapse = " "), ";"),
      "run;",
      source_duplicate_guard(paste0("_TFL_KKEY_", suffix),
                             c("chunk_order", "USUBJID"), suffix,
                             scope_field = "chunk_order")
    ) else character(),
    "/* Expand events once through the shared header membership. */",
    paste0("data ", chunks, ";"),
    "  length chunk_order 8;",
    unlist(lapply(plan$chunk_orders, function(order) c(
      paste0("  chunk_order = ", order, "; output;")
    )), use.names = FALSE),
    "  keep chunk_order;",
    "run;",
    "proc sql noprint;",
    paste0("  create table ", merged, " as"),
    "  select s.chunk_order, m.USUBJID, m.header_column_id, m.column_order,",
    "         s.source_row, s.row_order, s.node_key, s.denominator_eligible",
    paste0("  from ", pre, " as s inner join ", plan$membership_dataset, " as m"),
    "    on s.USUBJID = m.USUBJID",
    scaffold,
    "  ;",
    "quit;",
    paste0("data ", plan$input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", merged, ";"),
    "  keep chunk_order row_order column_order node_key USUBJID source_row ",
    "       denominator_eligible;",
    "run;"
  )
}

categorical_exclusive_guard_source <- function(plan, dataset, keys) {
  suffix <- sprintf("%03d", plan$batch_order)
  by_vars <- paste(c("chunk_order", "column_order", "node_key", keys, "row_order"), collapse = " ")
  last_key <- tail(keys, 1L)
  c(
    "/* Guard exclusive categorical overlap without changing counting events. */",
    paste0("proc sort data=", dataset, " out=_TFL_KGUARD_", suffix, ";"),
    paste0("  by ", by_vars, ";"),
    "run;",
    "data _null_;",
    "  length row_orders $32767;",
    "  retain row_orders overlap_count;",
    paste0("  set _TFL_KGUARD_", suffix, ";"),
    paste0("  by ", by_vars, ";"),
    paste0("  if first.", last_key, " then do; overlap_count = 0; row_orders = ''; end;"),
    "  overlap_count + 1;",
    "  row_orders = catx(',', row_orders, strip(put(row_order, best32.)));",
    paste0("  if last.", last_key, " and overlap_count > 1 then"),
    "    putlog 'WARNING: [USER] exclusive_overlap chunk_order=' chunk_order",
    paste0("      ' column_order=' column_order ' unit=' ", last_key, " ' row_orders=' row_orders '.';"),
    "run;"
  )
}

categorical_global_denominator_source <- function(plan, keys) {
  if (is.null(plan$global_denominator_source)) return(character())
  suffix <- sprintf("%03d", plan$batch_order)
  c(
    "/* Header-population record/key denominators use the full filtered container source. */",
    "proc sql noprint;",
    paste0("  create table _TFL_GDEN_INPUT_", suffix, " as"),
    "  select s.*, m.column_order",
    paste0("  from ", plan$global_denominator_source, " as s inner join _TFL_MEM_001 as m"),
    paste0("    on s.", plan$subject_key %||% "USUBJID", " = m.USUBJID;"),
    "quit;",
    paste0("proc sort data=_TFL_GDEN_INPUT_", suffix, " out=_TFL_GDEN_UNITS_", suffix, " nodupkey;"),
    paste0("  by column_order ", paste(keys, collapse = " "), ";"),
    "run;",
    paste0("data _TFL_GDEN_", suffix, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set _TFL_GDEN_UNITS_", suffix, ";"),
    "  chunk_order = 1; row_order = 0; node_key = '';",
    "  keep chunk_order row_order column_order node_key;",
    "run;"
  )
}

categorical_batch_analysis_source <- function(plan, exclusive = FALSE) {
  suffix <- sprintf("%03d", plan$batch_order)
  chunk <- plan$chunks[[1L]]
  numerator_keys <- primitive_counting_keys(chunk)
  denominator_keys <- primitive_counting_keys(chunk, chunk$denominator$unit %||% "distinct_subject")
  group_vars <- c("chunk_order", "column_order", "node_key")
  input_names <- vapply(plan$chunk_orders, function(order) {
    categorical_chunk_input_dataset(plan$batch_order, order)
  }, character(1L))
  has_global <- !is.null(plan$global_denominator_source)
  by_match <- "k.chunk_order = r.chunk_order and k.row_order = r.row_order and k.column_order = r.column_order"
  denominator_match <- "k.chunk_order = d.chunk_order and k.column_order = d.column_order and d.row_order = 0"
  if (!is.null(plan$nodes_dataset)) {
    by_match <- paste0(by_match, " and k.node_key = r.node_key")
    denominator_match <- paste0(denominator_match, if (has_global) " and d.node_key = ''" else " and k.node_key = d.node_key")
  }
  c(
    if (is.null(plan$nodes_dataset)) categorical_batch_source_input(plan) else c(
      "/* Combine normalized categorical counting events in template order. */",
      paste0("data ", plan$input_dataset, ";"),
      paste0("  set ", paste(input_names, collapse = " "), ";"),
      "run;"
    ),
    "/* Count declared units independently for denominator and numerator events. */",
    paste0("proc sort data=", plan$input_dataset, "(where=(row_order = 0)) out=_TFL_KDEN_", suffix, " nodupkey;"),
    paste0("  by ", paste(c(group_vars, denominator_keys), collapse = " "), ";"),
    "run;",
    paste0("proc sort data=", plan$input_dataset, "(where=(row_order > 0)) out=_TFL_KNUM_", suffix, " nodupkey;"),
    paste0("  by ", paste(c(group_vars, "row_order", numerator_keys), collapse = " "), ";"),
    "run;",
    if (exclusive) categorical_exclusive_guard_source(plan, paste0("_TFL_KNUM_", suffix), numerator_keys),
    categorical_global_denominator_source(plan, denominator_keys),
    paste0("data _TFL_KEVENT_", suffix, ";"),
    paste0("  set ", if (has_global) paste0("_TFL_GDEN_", suffix) else paste0("_TFL_KDEN_", suffix),
           " _TFL_KNUM_", suffix, ";"),
    "run;",
    "/* Analyze compatible categorical events once. */",
    paste0("proc freq data=_TFL_KEVENT_", suffix, " noprint;"),
    paste0("  tables ", paste(c(if (!is.null(plan$nodes_dataset)) "node_key",
                                "chunk_order", "row_order", "column_order"), collapse = "*"),
           " / out=", plan$raw_dataset, " missing;"),
    "run;",
    "/* Complete expected cells and use explicit denominator percentages. */",
    expected_cell_skeleton_source(plan),
    "proc sql noprint;",
    paste0("  create table _TFL_KJOIN_", suffix, " as"),
    "  select k.*, coalesce(r.count, 0) as numerator,",
    "    case when k.use_header_n = 1 then coalesce(h.header_n, 0)",
    "         else coalesce(d.count, 0) end as denominator",
    paste0("  from _TFL_KEY_", suffix, " as k left join ", plan$raw_dataset, " as r"),
    paste0("    on ", by_match),
    paste0("  left join ", plan$raw_dataset, " as d on ", denominator_match),
    "  left join _TFL_HN_001 as h on k.column_order = h.column_order;",
    "quit;",
    paste0("data ", plan$statistic_dataset, ";"),
    paste0("  set _TFL_KJOIN_", suffix, ";"),
    "  if denominator > 0 then pct = 100 * numerator / denominator;",
    "  else do; numerator = 0; pct = .; end;",
    "  if statistic_id = 'n' then do; value = numerator; estimable = 1; end;",
    "  else do; value = pct; estimable = denominator > 0; end;",
    "  base_digits = 0;",
    statistic_digits_source(),
    "run;",
    "/* Render categorical n and pct long-form cells. */",
    render_long_form_source(plan),
    "/* Literal percent characters remain unchanged during placeholder replacement. */"
  )
}

categorical_summary_emitter <- function(plan, resolved, exclusive) {
  expected_type <- if (exclusive) "categorical_summary_exclusive" else "categorical_summary_nonexclusive"
  if (!inherits(plan, "PrimitiveBatchPlan") || !identical(plan$chunk_type, expected_type)) {
    stop("Categorical emitter received an incompatible batch plan.", call. = FALSE)
  }
  sections <- lapply(seq_along(plan$chunks), function(index) {
    chunk_order <- plan$chunk_orders[[index]]
    new_source_section(
      paste0("categorical_chunk_", chunk_order), "chunk", plan$chunks[[index]]$id,
      chunk_order, categorical_chunk_source(plan, list(
        chunk_order = chunk_order, chunk = plan$chunks[[index]]
      ))
    )
  })
  sections <- c(sections, list(new_source_section(
    paste0("categorical_batch_", plan$batch_order), "analysis", expected_type,
    100L, paste(categorical_batch_analysis_source(plan, exclusive), collapse = "\n")
  )))
  new_emitter_output(sections, plan$statistic_dataset, plan$render_dataset)
}

categorical_summary_nonexclusive_emitter <- function(plan, resolved) {
  categorical_summary_emitter(plan, resolved, FALSE)
}

categorical_summary_exclusive_emitter <- function(plan, resolved) {
  categorical_summary_emitter(plan, resolved, TRUE)
}
