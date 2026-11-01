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

# The guard reads a key-only projection of the source, which is a different
# dataset from the filtered source above even though both derive from it.
categorical_guard_source_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_KGRD_%03d_%03d", batch_order, chunk_order)
}
categorical_combined_pre_dataset <- function(batch_order) {
  sprintf("_TFL_KPRE_%03d", batch_order)
}

categorical_batch_merged_dataset <- function(batch_order) {
  sprintf("_TFL_KMERGE_%03d", batch_order)
}

categorical_chunk_source <- function(plan, entry) {
  chunk <- entry$chunk
  source_dataset <- categorical_source_dataset(plan$batch_order, entry$chunk_order)
  merged_dataset <- categorical_merged_dataset(plan$batch_order, entry$chunk_order)
  input_dataset <- categorical_chunk_input_dataset(plan$batch_order, entry$chunk_order)
  numerator_keys <- primitive_counting_keys(chunk)
  filtered_source <- if (is.null(plan$nodes_dataset)) {
    primitive_source_filter(plan, entry, source_dataset, "categorical")
  } else character()
  # Duplicate checking is per chunk and runs on real source records, before any
  # header, denominator, analysis-row or scaffold expansion. The guard needs its
  # own chunk_order column, so it reads a small key-only projection rather than
  # the event table, which no longer carries one record per source row.
  guard_dataset <- categorical_guard_source_dataset(plan$batch_order, entry$chunk_order)
  check_keys <- primitive_check_keys(chunk)
  # Nested blocks carry a node_key; the same subject legitimately appears in
  # several nodes, so node identity has to be part of the duplicate key.
  guard_position_keys <- c("chunk_order", if (!is.null(plan$nodes_dataset)) "node_key")
  # Nested blocks must read the node-scoped level table rather than the merged
  # source, which the membership join has already broadcast across header
  # columns; counting that table would report broadcast copies as duplicates.
  guard_source <- if (!is.null(plan$node_source_dataset)) plan$node_source_dataset else source_dataset
  guard <- if (isTRUE(plan$include_duplicate_check) && length(check_keys)) c(
    "/* Keep one row per filtered source record for duplicate checking. */",
    paste0("data ", guard_dataset, ";"),
    paste0("  set ", guard_source, ";"),
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    paste0("  keep ", paste(unique(c(guard_position_keys, check_keys)), collapse = " "), ";"),
    "run;",
    source_block_duplicate_guard(
      guard_dataset, guard_position_keys, check_keys,
      sprintf("%03d_%03d", plan$batch_order, entry$chunk_order)
    )
  ) else character()
  pre_dataset <- categorical_chunk_pre_dataset(plan$batch_order, entry$chunk_order)
  row_output <- if (is.null(plan$nodes_dataset)) paste0("output ", pre_dataset, ";") else "output;"
  row_lines <- unlist(lapply(seq_along(chunk$rows), function(row_order) {
    row <- chunk$rows[[row_order]]
    if (!identical(row$type, "analysis")) return(character())
    paste0("    if (", row$condition, ") then do; row_order = ", row_order,
           "; ", row_output, " end;")
  }), use.names = FALSE)
  if (!is.null(plan$nodes_dataset)) return(paste(c(
    guard,
    primitive_source_input(plan, entry, source_dataset, merged_dataset, "categorical"),
    "/* Normalize numerator counting events within the anchor node. */",
    paste0("data ", input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", merged_dataset, ";"),
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    "  if not missing(source_row) then do;",
    row_lines,
    "  end;",
    paste0("  keep chunk_order row_order column_order node_key ",
           paste(numerator_keys, collapse = " "), ";"),
    "run;"
  ), collapse = "\n"))
  paste(c(
    filtered_source,
    guard,
    "/* Emit numerator counting events from the filtered chunk source. */",
    paste0("data ", pre_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", source_dataset, ";"),
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    "  if not missing(source_row) then do;",
    row_lines,
    "  end;",
    paste0("  keep ", paste(unique(c("chunk_order", "USUBJID", "source_row", "row_order",
                                      "node_key", numerator_keys)), collapse = " "), ";"),
    "run;"
  ), collapse = "\n")
}

categorical_batch_source_input <- function(plan) {
  suffix <- sprintf("%03d", plan$batch_order)
  pre <- categorical_combined_pre_dataset(plan$batch_order)
  merged <- categorical_batch_merged_dataset(plan$batch_order)
  input_names <- vapply(plan$chunk_orders, function(order) {
    categorical_chunk_pre_dataset(plan$batch_order, order)
  }, character(1L))
  # Declared distinct keys have to reach the analysis input, because the
  # numerator and denominator sorts group on them by name.
  extra_keys <- unique(unlist(lapply(plan$chunks, function(chunk) {
    primitive_counting_keys(chunk)
  }), use.names = FALSE))
  extra_keys <- setdiff(extra_keys, c("chunk_order", "USUBJID", "source_row"))
  c(
    "/* Combine normalized categorical events before one membership merge. */",
    paste0("data ", pre, ";"),
    paste0("  set ", paste(input_names, collapse = " "), ";"),
    "run;",
    "/* Expand events once through the shared header membership. */",
    "proc sql noprint;",
    paste0("  create table ", merged, " as"),
    "  select s.chunk_order, m.USUBJID, m.header_column_id, m.column_order,",
    "         s.source_row, s.row_order, s.node_key",
    # Declared distinct keys must survive the join, otherwise later BY lists
    # reference variables that no longer exist.
    if (length(extra_keys)) paste0("         , s.", extra_keys, collapse = "\n"),
    paste0("  from ", pre, " as s inner join ", plan$membership_dataset, " as m"),
    "    on s.USUBJID = m.USUBJID",
    "  ;",
    "quit;",
    paste0("data ", plan$input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", merged, ";"),
    "  keep chunk_order row_order column_order node_key USUBJID source_row ",
    if (length(extra_keys)) paste0(" ", paste(extra_keys, collapse = " ")),
    ";",
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

categorical_denominator_source <- function(plan, entry) {
  chunk <- entry$chunk
  denominator <- chunk$denominator
  suffix <- sprintf("%03d_%03d", plan$batch_order, entry$chunk_order)
  qualified <- paste0("_TFL_KDQUAL_", suffix)
  units <- paste0("_TFL_KDUNIT_", suffix)
  events <- paste0("_TFL_KDEN_", suffix)
  current_group <- identical(denominator$scope, "current_group")
  keys <- denominator_counting_keys(denominator)
  position_keys <- c("column_order", if (current_group) "node_key")
  qualification <- if (!is.null(denominator$expression)) {
    paste0("  if not (", denominator$expression, ") then delete;")
  } else character()
  if (identical(denominator$scope, "header_population")) {
    input <- c(
      if (is.null(denominator$expression))
        "/* Reuse resolved membership columns without re-evaluating source predicates. */" else
        "/* Qualify header subjects while the population source variables are available. */",
      paste0("data ", qualified, ";"),
      paste0("  set ", if (is.null(denominator$expression)) plan$membership_dataset else
               plan$header_population_dataset, ";"),
      if (!is.null(denominator$expression)) unlist(lapply(seq_along(plan$header_columns), function(index) {
        column <- plan$header_columns[[index]]
        paste0("  if (", column$condition, ") and (",
               denominator$expression, ") then do; column_order = ",
               index, "; output; end;")
      }), use.names = FALSE),
      "  keep column_order USUBJID;",
      "run;"
    )
  } else {
    # Full-source denominators are joined before any level excludes records.
    # Current-group input is already an inner membership join at the anchor.
    merged <- if (current_group) chunk$source_data else paste0("_TFL_KDMERGE_", suffix)
    source <- if (!is.null(plan$chunk_source_dataset)) plan$chunk_source_dataset else
      categorical_source_dataset(plan$batch_order, entry$chunk_order)
    input <- c(
      if (!current_group) c(
        "/* Expand the complete filtered source through header membership for this denominator. */",
        "proc sql noprint;",
        paste0("  create table ", merged, " as"),
        "  select s.*, m.column_order",
        paste0("  from ", source, " as s inner join ", plan$membership_dataset, " as m"),
        "    on s.USUBJID = m.USUBJID;",
        "quit;"
      ),
      "/* Apply denominator qualification before projecting and collapsing its identity keys. */",
      paste0("data ", qualified, ";"),
      paste0("  set ", merged, ";"),
      qualification,
      paste0("  keep ", paste(unique(c(position_keys, keys)), collapse = " "), ";"),
      "run;"
    )
  }
  c(
    input,
    if (!identical(denominator$unit, "record")) c(
      paste0("proc sort data=", qualified, " out=", units, " nodupkey;"),
      paste0("  by ", paste(unique(c(position_keys, keys)), collapse = " "), ";"),
      "run;"
    ),
    "/* Emit one denominator event per qualified unit independently of numerator rows. */",
    paste0("data ", events, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", if (identical(denominator$unit, "record")) qualified else units, ";"),
    if (!current_group) "  node_key = '';",
    paste0("  chunk_order = ", entry$chunk_order, "; row_order = 0;"),
    "  keep chunk_order row_order column_order node_key;",
    "run;"
  )
}

categorical_batch_analysis_source <- function(plan, exclusive = FALSE) {
  suffix <- sprintf("%03d", plan$batch_order)
  chunk <- plan$chunks[[1L]]
  numerator_keys <- primitive_counting_keys(chunk)
  group_vars <- c("chunk_order", "column_order", "node_key")
  input_names <- vapply(plan$chunk_orders, function(order) {
    categorical_chunk_input_dataset(plan$batch_order, order)
  }, character(1L))
  has_global <- !identical(chunk$denominator$scope, "current_group")
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
    "/* Collapse numerator units within each analysis row and column. */",
    paste0("proc sort data=", plan$input_dataset, "(where=(row_order > 0)) out=_TFL_KNUM_", suffix, " nodupkey;"),
    paste0("  by ", paste(c(group_vars, "row_order", numerator_keys), collapse = " "), ";"),
    "run;",
    if (exclusive) categorical_exclusive_guard_source(plan, paste0("_TFL_KNUM_", suffix), numerator_keys),
    unlist(lapply(seq_along(plan$chunks), function(index) {
      categorical_denominator_source(plan, list(chunk_order = plan$chunk_orders[[index]],
                                                chunk = plan$chunks[[index]]))
    }), use.names = FALSE),
    paste0("data _TFL_KEVENT_", suffix, ";"),
    paste0("  set ", paste(sprintf("_TFL_KDEN_%03d_%03d", plan$batch_order, plan$chunk_orders),
                              collapse = " "), " _TFL_KNUM_", suffix, ";"),
    "  flag = 1;",
    "  keep chunk_order row_order column_order node_key flag;",
    "run;",
    "/* Build the logical class catalog before PROC MEANS supplies zero combinations. */",
    expected_cell_skeleton_source(plan),
    "/* Include denominator positions so EXCLUSIVE retains their counting events. */",
    paste0("data _TFL_KCLASS_", suffix, ";"),
    paste0("  set _TFL_KEY_", suffix, "(keep=chunk_order row_order column_order node_key);"),
    "  output;",
    "  row_order = 0;",
    if (has_global) "  node_key = '';",
    "  output;",
    "run;",
    paste0("proc sort data=_TFL_KCLASS_", suffix, " nodupkey;"),
    "  by chunk_order row_order column_order node_key;",
    "run;",
    "/* Analyze compatible categorical events once with PROC MEANS. */",
    paste0("proc means data=_TFL_KEVENT_", suffix, " classdata=_TFL_KCLASS_", suffix,
           " nway completetypes exclusive noprint;"),
    paste0("  class ", paste(c(if (!is.null(plan$nodes_dataset)) "node_key",
                                "chunk_order", "row_order", "column_order"), collapse = " "),
           " / missing;"),
    "  var flag;",
    paste0("  output out=", plan$raw_dataset, "(drop=_type_ _freq_) n=count;"),
    "run;",
    "/* Attach logical metadata and use explicit denominator percentages. */",
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
    "  else pct = .;",
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
