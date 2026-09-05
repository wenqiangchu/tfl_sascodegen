# Source emitter for continuous primitive batches.

continuous_source_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_CSRC_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

continuous_merged_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_CMERGE_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

continuous_chunk_input_dataset <- function(batch_order, chunk_order) {
  paste0("_TFL_CIN_", sprintf("%03d", batch_order), "_", sprintf("%03d", chunk_order))
}

continuous_chunk_source <- function(plan, entry) {
  batch <- plan$batch_order
  chunk_order <- entry$chunk_order
  chunk <- entry$chunk
  source_dataset <- continuous_source_dataset(batch, chunk_order)
  merged_dataset <- continuous_merged_dataset(batch, chunk_order)
  input_dataset <- continuous_chunk_input_dataset(batch, chunk_order)
  filter_lines <- if (!is.null(chunk$filter)) {
    c(paste0("  if not (", chunk$filter, ") then delete;"))
  } else character()
  source_lines <- c(
    "/* Filter continuous chunk source before merge. */",
    paste0("data ", source_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    filter_lines,
    "  source_row + 1;",
    "run;",
    "/* Merge continuous chunk source with header membership. */",
    paste0("data ", merged_dataset, ";"),
    paste0("  merge ", plan$membership_dataset, "(in=membership) ", source_dataset, "(in=source);"),
    "  by USUBJID;",
    "  if membership;",
    "run;"
  )
  input_lines <- c(
    "/* Normalize continuous analysis values into the batch input. */",
    paste0("data ", input_dataset, ";"),
    paste0("  set ", merged_dataset, ";"),
    paste0("  chunk_order = ", chunk_order, ";"),
    "  analysis_value = ", chunk$analysis_variable, ";",
    "  keep chunk_order column_order analysis_value source_row;",
    "run;"
  )
  paste(c(source_lines, input_lines), collapse = "\n")
}

continuous_batch_analysis_source <- function(plan) {
  chunk_inputs <- vapply(plan$chunk_orders, function(chunk_order) {
    continuous_chunk_input_dataset(plan$batch_order, chunk_order)
  }, character(1L))
  c(
    "/* Combine normalized continuous chunk inputs in template order. */",
    paste0("data ", plan$input_dataset, ";"),
    paste0("  set ", paste(chunk_inputs, collapse = " "), ";"),
    "run;",
    "/* Resolve continuous precision digits from eligible subjects. */",
    paste0("data ", plan$precision_dataset, ";"),
    paste0("  set ", plan$input_dataset, ";"),
    "  keep chunk_order source_row analysis_value;",
    "run;",
    "/* Provide all continuous chunk and header keys. */",
    paste0("data _TFL_CKEY_", sprintf("%03d", plan$batch_order), ";"),
    "  set _TFL_MEM_001;",
    "  keep chunk_order column_order;",
    "run;",
    "/* Analyze compatible continuous chunks once. */",
    paste0("proc means data=", plan$input_dataset, " nway;"),
    "  class chunk_order column_order;",
    "  var analysis_value;",
    paste0("  output out=", plan$raw_dataset,
           "(drop=_TYPE_ _FREQ_) N=_n MEAN=_mean STD=_sd MEDIAN=_median",
           " Q1=_q1 Q3=_q3 MIN=_min MAX=_max;"),
    "run;",
    expected_cell_skeleton_source(plan),
    long_form_statistic_source(plan, "_mean"),
    render_long_form_source(plan)
  )
}

continuous_summary_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "continuous_summary")) {
    stop("Continuous emitter received an incompatible batch plan.", call. = FALSE)
  }
  chunk_sections <- lapply(plan$chunks, function(chunk) {
    entry <- plan$logical_maps[[which(vapply(plan$logical_maps, `[[`, "", "chunk_id") == chunk$id)[[1L]]]]
    new_source_section(
      paste0("continuous_chunk_", entry$chunk_order), "chunk", chunk$id,
      entry$chunk_order, continuous_chunk_source(plan, list(
        chunk_order = entry$chunk_order, chunk = chunk
      ))
    )
  })
  batch_text <- paste(continuous_batch_analysis_source(plan), collapse = "\n")
  sections <- c(chunk_sections, list(new_source_section(
    paste0("continuous_batch_", plan$batch_order), "analysis", "continuous",
    100L, batch_text
  )))
  new_emitter_output(sections, plan$statistic_dataset, plan$render_dataset)
}
