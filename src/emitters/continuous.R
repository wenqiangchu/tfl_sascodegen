# Source emitter for continuous primitive batches.

continuous_source_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_CSRC_%03d_%03d", batch_order, chunk_order)
}

continuous_merged_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_CMERGE_%03d_%03d", batch_order, chunk_order)
}

continuous_chunk_input_dataset <- function(batch_order, chunk_order) {
  sprintf("_TFL_CIN_%03d_%03d", batch_order, chunk_order)
}

continuous_combined_source_dataset <- function(batch_order) {
  sprintf("_TFL_CPRE_%03d", batch_order)
}

continuous_batch_chunks_dataset <- function(batch_order) {
  sprintf("_TFL_CCHUNKS_%03d", batch_order)
}

continuous_batch_merged_dataset <- function(batch_order) {
  sprintf("_TFL_CMERGE_%03d", batch_order)
}

continuous_counting_unit_dataset <- function(batch_order) {
  sprintf("_TFL_CUNIT_%03d", batch_order)
}

continuous_chunk_source <- function(plan, entry) {
  source_dataset <- continuous_source_dataset(plan$batch_order, entry$chunk_order)
  input_dataset <- continuous_chunk_input_dataset(plan$batch_order, entry$chunk_order)
  if (!is.null(plan$nodes_dataset)) {
    merged_dataset <- continuous_merged_dataset(plan$batch_order, entry$chunk_order)
    unit_keys <- primitive_counting_keys(entry$chunk)
    keep_fields <- unique(c("chunk_order", "column_order", "analysis_value",
                            "source_row", "node_key", unit_keys))
    # A single nested chunk already has the complete batch input schema.
    input_outputs <- c(input_dataset, if (length(plan$chunks) == 1L) plan$input_dataset)
    return(paste(c(
      primitive_source_input(plan, entry, source_dataset, merged_dataset, "continuous"),
      "/* Normalize continuous analysis values into the batch input. */",
      paste0("data ", paste(input_outputs, collapse = " "), ";"),
      "  length node_key $&_TFL_NODE_LEN;",
      paste0("  set ", merged_dataset, ";"),
      paste0("  chunk_order = ", entry$chunk_order, ";"),
      paste0("  analysis_value = ", entry$chunk$analysis_variable, ";"),
      paste0("  keep ", paste(keep_fields, collapse = " "), ";"),
      "run;"
    ), collapse = "\n"))
  }
  paste(c(
    "/* Filter continuous chunk source before merge. */",
    "/* Normalize continuous analysis values before the batch merge. */",
    paste0("data ", input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", entry$chunk$source_data, ";"),
    if (!is.null(entry$chunk$filter)) {
      paste0("  if not (", entry$chunk$filter, ") then delete;")
    } else character(),
    "  source_row = _n_;",
    paste0("  chunk_order = ", entry$chunk_order, ";"),
    paste0("  analysis_value = ", entry$chunk$analysis_variable, ";"),
    "  keep chunk_order USUBJID analysis_value source_row node_key;",
    "run;"
  ), collapse = "\n")
}

continuous_batch_source_input <- function(plan) {
  suffix <- sprintf("%03d", plan$batch_order)
  combined <- continuous_combined_source_dataset(plan$batch_order)
  chunks <- continuous_batch_chunks_dataset(plan$batch_order)
  merged <- continuous_batch_merged_dataset(plan$batch_order)
  chunk_inputs <- vapply(plan$chunk_orders, function(chunk_order) {
    continuous_chunk_input_dataset(plan$batch_order, chunk_order)
  }, character(1L))
  subject_key <- plan$subject_key %||% "USUBJID"
  dedup_keys <- c("chunk_order", subject_key)
  dedup <- if (isTRUE(plan$auto_dedup)) {
    source_auto_dedup_guard(combined, dedup_keys, suffix)
  } else {
    list(source = character(), dataset = combined)
  }
  chunk_rows <- unlist(lapply(plan$chunk_orders, function(chunk_order) {
    paste0("  chunk_order = ", chunk_order, "; output;")
  }), use.names = FALSE)
  c(
    "/* Combine normalized continuous chunk inputs before one membership merge. */",
    paste0("data ", combined, ";"),
    paste0("  set ", paste(chunk_inputs, collapse = " "), ";"),
    "run;",
    # Deduplication runs first so the optional check reports the retained source.
    dedup$source,
    if (isTRUE(plan$include_duplicate_check)) {
      source_duplicate_guard(dedup$dataset, dedup_keys, suffix,
                             scope_field = "chunk_order")
    } else character(),
    "/* Preserve one scaffold row for every batch chunk and membership row. */",
    paste0("data ", chunks, ";"),
    "  length chunk_order 8;",
    chunk_rows,
    "  keep chunk_order;",
    "run;",
    "proc sql noprint;",
    paste0("  create table ", merged, " as"),
    "  select b.chunk_order, m.USUBJID, m.header_column_id, m.column_order,",
    "         s.source_row, s.analysis_value, '' as node_key length=&_TFL_NODE_LEN",
    paste0("  from ", chunks, " as b cross join ", plan$membership_dataset, " as m"),
    paste0("  left join ", dedup$dataset, " as s"),
    paste0("    on s.chunk_order = b.chunk_order and s.", subject_key, " = m.USUBJID;"),
    "quit;",
    paste0("data ", plan$input_dataset, ";"),
    "  length node_key $&_TFL_NODE_LEN;",
    paste0("  set ", merged, ";"),
    "  keep chunk_order column_order analysis_value source_row node_key;",
    "run;"
  )
}

continuous_counting_unit_source <- function(plan) {
  if (is.null(plan$nodes_dataset)) {
    return(list(source = character(), dataset = plan$input_dataset))
  }
  chunk <- plan$chunks[[1L]]
  unit <- chunk$counting_unit %||% "record"
  if (identical(unit, "record")) {
    return(list(source = character(), dataset = plan$input_dataset))
  }
  suffix <- sprintf("%03d", plan$batch_order)
  dataset <- continuous_counting_unit_dataset(plan$batch_order)
  sorted_dataset <- paste0("_TFL_CUNIT_SORT_", suffix)
  unit_keys <- primitive_counting_keys(chunk, unit)
  group_vars <- unique(c("chunk_order", "column_order", "node_key", unit_keys))
  sort_vars <- unique(c(group_vars, "source_row"))
  last_key <- tail(group_vars, 1L)
  diagnostic_keys <- unlist(lapply(unit_keys, function(key) {
    paste0("      ' ", key, "=' ", key)
  }), use.names = FALSE)
  list(
    source = c(
      paste0("/* Materialize one continuous value per ", unit,
             " counting unit without implicit value selection. */"),
      paste0("proc sort data=", plan$input_dataset, " out=", sorted_dataset, ";"),
      paste0("  by ", paste(sort_vars, collapse = " "), ";"),
      "run;",
      paste0("data ", dataset, ";"),
      paste0("  set ", sorted_dataset, ";"),
      paste0("  by ", paste(group_vars, collapse = " "), ";"),
      "  retain _tfl_nonmissing_count _tfl_analysis_value _tfl_source_row;",
      paste0("  if first.", last_key, " then do;"),
      "    _tfl_nonmissing_count = 0;",
      "    call missing(_tfl_analysis_value, _tfl_source_row);",
      "  end;",
      "  if not missing(analysis_value) then do;",
      "    _tfl_nonmissing_count + 1;",
      "    if _tfl_nonmissing_count = 1 then do;",
      "      _tfl_analysis_value = analysis_value;",
      "      _tfl_source_row = source_row;",
      "    end;",
      "  end;",
      paste0("  if last.", last_key, " then do;"),
      "    if _tfl_nonmissing_count > 1 then do;",
      "      putlog 'ERROR: [USER] continuous_unit_multiple_values'",
      paste0("      ' counting_unit=", unit, "'"),
      "      ' chunk_order=' chunk_order",
      "      ' column_order=' column_order",
      "      ' node_key=' node_key",
      diagnostic_keys,
      "      ' nonmissing_count=' _tfl_nonmissing_count '.';",
      "      abort cancel;",
      "    end;",
      "    analysis_value = _tfl_analysis_value;",
      "    source_row = _tfl_source_row;",
      "    output;",
      "  end;",
      "  keep chunk_order column_order analysis_value source_row node_key;",
      "run;"
    ),
    dataset = dataset
  )
}

continuous_precision_source <- function(plan, input_dataset = plan$input_dataset) {
  suffix <- sprintf("%03d", plan$batch_order)
  c(
    "/* Resolve continuous precision digits from eligible source records once per node. */",
    paste0("proc sort data=", input_dataset,
           "(where=(not missing(analysis_value))) out=_TFL_CPINPUT_", suffix, " nodupkey;"),
    "  by chunk_order node_key source_row;",
    "run;",
    paste0("data _TFL_CPDIGITS_", suffix, ";"),
    "  length precision_text mantissa $64;",
    paste0("  set _TFL_CPINPUT_", suffix, ";"),
    "  precision_text = strip(put(analysis_value, e32.14));",
    "  exponent = input(scan(precision_text, 2, 'Ee'), best32.);",
    "  mantissa = prxchange('s/0+$//', 1, strip(scan(precision_text, 1, 'Ee')));",
    "  decimal_position = index(mantissa, '.');",
    "  fraction_digits = ifn(decimal_position > 0, lengthn(mantissa) - decimal_position, 0);",
    "  base_digits = max(0, fraction_digits - exponent);",
    "run;",
    "proc sql noprint;",
    paste0("  create table ", plan$precision_dataset, " as"),
    "  select chunk_order, node_key, max(base_digits) as base_digits",
    paste0("  from _TFL_CPDIGITS_", suffix, " group by chunk_order, node_key;"),
    "quit;"
  )
}

continuous_statistic_join_source <- function(plan) {
  suffix <- sprintf("%03d", plan$batch_order)
  node_match <- if (!is.null(plan$nodes_dataset)) " and k.node_key = r.node_key" else ""
  c(
    "/* Map analysis output to the common long-form statistic identity. */",
    "/* Complete continuous statistics from the expected-cell key map. */",
    "proc sql noprint;",
    paste0("  create table _TFL_CJOIN_", suffix, " as"),
    "  select k.*, r._n, r._mean, r._sd, r._median, r._q1, r._q3, r._min, r._max,",
    "    coalesce(p.base_digits, 0) as base_digits",
    paste0("  from _TFL_KEY_", suffix, " as k left join ", plan$raw_dataset, " as r"),
    paste0("    on k.chunk_order = r.chunk_order and k.column_order = r.column_order", node_match),
    paste0("  left join ", plan$precision_dataset, " as p"),
    "    on k.chunk_order = p.chunk_order and k.node_key = p.node_key;",
    "quit;"
  )
}

continuous_statistic_value_source <- function() {
  c(
    "  select (statistic_id);",
    "    when ('n') value = coalesce(_n, 0);",
    "    when ('mean') value = _mean;",
    "    when ('sd') value = _sd;",
    "    when ('median') value = _median;",
    "    when ('q1') value = _q1;",
    "    when ('q3') value = _q3;",
    "    when ('min') value = _min;",
    "    when ('max') value = _max;",
    "    otherwise value = .;",
    "  end;",
    "  estimable = not missing(value);",
    statistic_digits_source()
  )
}

continuous_key_statistic_source <- function(plan) {
  c(
    continuous_statistic_join_source(plan),
    paste0("data ", plan$statistic_dataset, ";"),
    sprintf("  set _TFL_CJOIN_%03d;", plan$batch_order),
    continuous_statistic_value_source(),
    "run;"
  )
}

continuous_batch_preparation <- function(plan) {
  counting_unit <- continuous_counting_unit_source(plan)
  source <- c(
    if (is.null(plan$nodes_dataset)) continuous_batch_source_input(plan) else if (length(plan$chunks) > 1L) {
      chunk_inputs <- vapply(plan$chunk_orders, function(chunk_order) {
        continuous_chunk_input_dataset(plan$batch_order, chunk_order)
      }, character(1L))
      c(
        "/* Combine normalized continuous chunk inputs in template order. */",
        paste0("data ", plan$input_dataset, ";"),
        paste0("  set ", paste(chunk_inputs, collapse = " "), ";"),
        "run;"
      )
    },
    counting_unit$source,
    continuous_precision_source(plan, counting_unit$dataset)
  )
  list(source = source, dataset = counting_unit$dataset)
}

continuous_means_source <- function(input_dataset, raw_dataset, class_variables) {
  c(
    "/* Analyze compatible continuous chunks once. */",
    paste0("proc means data=", input_dataset, " nway noprint;"),
    paste0("  class ", paste(class_variables, collapse = " "), ";"),
    "  var analysis_value;",
    paste0("  output out=", raw_dataset,
           "(drop=_TYPE_ _FREQ_) N=_n MEAN=_mean STD=_sd MEDIAN=_median",
           " Q1=_q1 Q3=_q3 MIN=_min MAX=_max;"),
    "run;"
  )
}

continuous_batch_result_source <- function(plan) {
  c(
    expected_cell_skeleton_source(plan),
    continuous_key_statistic_source(plan),
    render_long_form_source(plan)
  )
}

continuous_batch_analysis_source <- function(plan) {
  prepared <- continuous_batch_preparation(plan)
  c(
    prepared$source,
    continuous_means_source(prepared$dataset, plan$raw_dataset,
                            c("chunk_order", "column_order",
                              if (!is.null(plan$nodes_dataset)) "node_key")),
    continuous_batch_result_source(plan)
  )
}

continuous_summary_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "continuous_summary")) {
    stop("Continuous emitter received an incompatible batch plan.", call. = FALSE)
  }
  sections <- lapply(seq_along(plan$chunks), function(index) {
    chunk_order <- plan$chunk_orders[[index]]
    new_source_section(
      paste0("continuous_chunk_", chunk_order), "chunk", plan$chunks[[index]]$id,
      chunk_order, continuous_chunk_source(plan, list(
        chunk_order = chunk_order, chunk = plan$chunks[[index]]
      ))
    )
  })
  sections <- c(sections, list(new_source_section(
    paste0("continuous_batch_", plan$batch_order), "analysis", "continuous",
    100L, paste(continuous_batch_analysis_source(plan), collapse = "\n")
  )))
  new_emitter_output(sections, plan$statistic_dataset, plan$render_dataset)
}
