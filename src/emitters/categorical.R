# Source emitter for nonexclusive categorical primitive batches.

categorical_source_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_KSRC_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

categorical_merged_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_KMERGE_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

categorical_chunk_input_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_KIN_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

categorical_chunk_source <- function(plan, entry) {
  batch <- plan$batch_order
  chunk_order <- entry$chunk_order
  chunk <- entry$chunk
  source_dataset <- categorical_source_dataset(batch, chunk_order)
  merged_dataset <- categorical_merged_dataset(batch, chunk_order)
  input_dataset <- categorical_chunk_input_dataset(batch, chunk_order)
  filter_lines <- if (!is.null(chunk$filter)) {
    paste0("  if not (", chunk$filter, ") then delete;")
  } else NULL
  denominator <- chunk$denominator$type
  denominator_lines <- switch(
    denominator,
    header_population = "  denominator_eligible = 1;",
    non_missing = paste0("  denominator_eligible = not missing(", chunk$denominator$variable, ");"),
    custom = paste0("  denominator_eligible = (", chunk$denominator$expression, ");"),
    "  denominator_eligible = 1;"
  )
  row_lines <- unlist(lapply(seq_along(chunk$rows), function(row_order) {
    row <- chunk$rows[[row_order]]
    if (!identical(row$type, "analysis")) return(character())
    c(
      paste0("  if (", row$condition, ") then do;"),
      paste0("    row_order = ", row_order, ";"),
      "    output;",
      "  end;"
    )
  }), use.names = FALSE)
  input_lines <- c(
    "/* Filter categorical chunk source before merge. */",
    paste0("data ", source_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    filter_lines,
    "  source_row + 1;",
    "run;",
    "/* Merge categorical chunk source with header membership. */",
    paste0("data ", merged_dataset, ";"),
    paste0("  merge ", plan$membership_dataset, "(in=membership) ", source_dataset, "(in=source);"),
    "  by USUBJID;",
    "  if membership;",
    "run;",
    "/* Normalize denominator and numerator counting events. */",
    paste0("data ", input_dataset, ";"),
    paste0("  set ", merged_dataset, ";"),
    paste0("  chunk_order = ", chunk_order, ";"),
    denominator_lines,
    "  if denominator_eligible then do;",
    "    row_order = 0; output;",
    "  end;",
    "  if missing(USUBJID) then delete;",
    row_lines,
    "  keep chunk_order row_order column_order source_row;",
    "run;"
  )
  paste(input_lines, collapse = "\n")
}

categorical_batch_analysis_source <- function(plan) {
  chunk_inputs <- vapply(plan$chunk_orders, function(chunk_order) {
    categorical_chunk_input_dataset(plan$batch_order, chunk_order)
  }, character(1L))
  c(
    "/* Combine normalized categorical counting events in template order. */",
    paste0("data ", plan$input_dataset, ";"),
    paste0("  set ", paste(chunk_inputs, collapse = " "), ";"),
    "run;",
    "/* Analyze compatible categorical events once. */",
    paste0("proc freq data=", plan$input_dataset, ";"),
    paste0("  tables chunk_order*row_order*column_order / out=", plan$raw_dataset, ";"),
    "run;",
    "/* Complete expected cells and use explicit denominator percentages. */",
    expected_cell_skeleton_source(plan),
    "  /* Expected-cell skeleton supplies zero counts; FREQ PERCENT is ignored. */",
    paste0("data ", plan$statistic_dataset, ";"),
    "  length chunk_id row_id header_column_id statistic_id $128;",
    paste0("  set ", plan$raw_dataset, ";"),
    "  denominator = 0; numerator = count;",
    "  if denominator > 0 then pct = 100 * numerator / denominator;",
    "  else do; pct = .; estimable = 0; end;",
    "run;",
    "/* Render categorical n and pct long-form cells. */",
    render_long_form_source(plan),
    "/* Literal percent characters remain unchanged during placeholder replacement. */"
  )
}

categorical_exclusive_batch_analysis_source <- function(plan) {
  lines <- categorical_batch_analysis_source(plan)
  guard <- c(
    "/* Guard exclusive categorical overlap without changing counting events. */",
    paste0("proc sort data=", plan$input_dataset, " out=_TFL_KGUARD_", sprintf("%03d", plan$batch_order), ";"),
    "  by chunk_order column_order;",
    "run;",
    "data _null_;",
    paste0("  set _TFL_KGUARD_", sprintf("%03d", plan$batch_order), ";"),
    "  by chunk_order column_order;",
    "  if first.column_order then overlap_count = 0;",
    "  if row_order > 0 then overlap_count + 1;",
    "  if last.column_order and overlap_count > 1 then",
    "    put 'WARNING: [USER] exclusive_overlap chunk_order=' chunk_order",
    "      ' column_order=' column_order ' unit=' USUBJID ' row_orders=' row_order '.';",
    "run;"
  )
  c(lines[1:3], guard, lines[4:length(lines)])
}

categorical_summary_nonexclusive_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "categorical_summary_nonexclusive")) {
    stop("Categorical emitter received an incompatible batch plan.", call. = FALSE)
  }
  chunk_sections <- lapply(plan$chunks, function(chunk) {
    entry <- plan$logical_maps[[which(vapply(plan$logical_maps, `[[`, "", "chunk_id") == chunk$id)[[1L]]]]
    new_source_section(
      paste0("categorical_chunk_", entry$chunk_order), "chunk", chunk$id,
      entry$chunk_order, categorical_chunk_source(plan, list(
        chunk_order = entry$chunk_order, chunk = chunk
      ))
    )
  })
  sections <- c(chunk_sections, list(new_source_section(
    paste0("categorical_batch_", plan$batch_order), "analysis", "categorical_nonexclusive",
    100L, paste(categorical_batch_analysis_source(plan), collapse = "\n")
  )))
  new_emitter_output(sections, plan$statistic_dataset, plan$render_dataset)
}

categorical_summary_exclusive_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "categorical_summary_exclusive")) {
    stop("Exclusive categorical emitter received an incompatible batch plan.", call. = FALSE)
  }
  chunk_sections <- lapply(plan$chunks, function(chunk) {
    entry <- plan$logical_maps[[which(vapply(plan$logical_maps, `[[`, "", "chunk_id") == chunk$id)[[1L]]]]
    new_source_section(
      paste0("categorical_exclusive_chunk_", entry$chunk_order), "chunk", chunk$id,
      entry$chunk_order, categorical_chunk_source(plan, list(
        chunk_order = entry$chunk_order, chunk = chunk
      ))
    )
  })
  sections <- c(chunk_sections, list(new_source_section(
    paste0("categorical_exclusive_batch_", plan$batch_order), "analysis", "categorical_exclusive",
    100L, paste(categorical_exclusive_batch_analysis_source(plan), collapse = "\n")
  )))
  new_emitter_output(sections, plan$statistic_dataset, plan$render_dataset)
}
