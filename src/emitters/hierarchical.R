# Source emitter for hierarchical containers. Containers are never cross-batched.

hierarchical_source_dataset <- function(batch_order) {
  paste0("_TFL_HNODE_", sprintf("%03d", batch_order))
}

hierarchical_summary_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "hierarchical_summary") || length(plan$chunks) != 1L) {
    stop("Hierarchical emitter received an incompatible batch plan.", call. = FALSE)
  }
  chunk <- plan$chunks[[1L]]
  node_dataset <- hierarchical_source_dataset(plan$batch_order)
  level_lines <- unlist(lapply(seq_along(chunk$levels), function(index) {
    level <- chunk$levels[[index]]
    c(
      paste0("/* Discover hierarchical level ", index, " nodes. */"),
      paste0("proc sort data=", chunk$source_data, " out=_TFL_HLEVEL_",
             sprintf("%03d", index), ";"),
      paste0("  by ", level$order_variable, ";"),
      "run;",
      paste0("data _TFL_HLEVEL_", sprintf("%03d", index), ";"),
      paste0("  set _TFL_HLEVEL_", sprintf("%03d", index), ";"),
      paste0("  group_path = cats('L', ", index, ", ':', ", level$variable, ");"),
      paste0("  node_key = cats('L', ", index, ", ':', ", level$variable, ");"),
      "run;"
    )
  }), use.names = FALSE)
  block_lines <- unlist(lapply(seq_along(chunk$analysis_blocks), function(index) {
    block <- chunk$analysis_blocks[[index]]
    c(
      paste0("/* Dispatch hierarchical analysis block ", block$id, " within node scope. */"),
      paste0("/* Nested primitive type: ", block$type, "; anchor level: ", block$anchor_level, ". */")
    )
  }), use.names = FALSE)
  text <- c(
    "/* Filter and guard hierarchical source before level discovery. */",
    paste0("data ", node_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;") else character(),
    "run;",
    level_lines,
    "/* Order static rows before dynamic children and preserve result sort metadata. */",
    block_lines,
    paste0("data ", plan$render_dataset, ";"),
    "  length chunk_id row_id label indent_level header_column_id cell_text $256;",
    paste0("  set ", node_dataset, ";"),
    "  /* Hierarchical render rows carry runtime_row_id, row_role, group_path, and node_key. */",
    "run;"
  )
  new_emitter_output(
    list(new_source_section(
      paste0("hierarchical_", plan$batch_order), "hierarchical", chunk$id,
      100L, paste(text, collapse = "\n")
    )), plan$statistic_dataset, plan$render_dataset
  )
}
