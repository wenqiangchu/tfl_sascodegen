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
  record_key <- chunk$source_contract$record_key %||% character()
  duplicate_guard <- if (length(record_key) > 0L) c(
    "/* Guard hierarchical record keys without changing source records. */",
    paste0("proc sort data=", node_dataset, " out=_TFL_HGUARD_", sprintf("%03d", plan$batch_order), ";"),
    paste0("  by ", paste(record_key, collapse = " "), ";"),
    "run;",
    "data _null_;",
    paste0("  set _TFL_HGUARD_", sprintf("%03d", plan$batch_order), ";"),
    paste0("  by ", paste(record_key, collapse = " "), ";"),
    "  if not first.", record_key[[1L]], " then put 'WARNING: [USER] duplicate_key';",
    "run;"
  ) else character()
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
      paste0("  level_component = cats(lengthn(strip(", level$variable, ")), ':', strip(", level$variable, "));"),
      if (index == 1L) "  group_path = level_component;" else
        "  group_path = cats(group_path, '|', level_component);",
      "  node_key = group_path;",
      switch(level$missing_policy,
             exclude = paste0("  if missing(", level$variable, ");"),
             label = paste0("  if missing(", level$variable, ") then ",
                            "group_label = ", sas_character_literal(level$missing_label %||% "Missing"), ";"),
             error = paste0("  if missing(", level$variable, ") then do; put 'WARNING: [USER] missing_level'; delete; end;"),
             character()),
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
    duplicate_guard,
    level_lines,
    "/* Order static rows before dynamic children and preserve result sort metadata. */",
    block_lines,
    "/* Map nested primitive results to hierarchical identities. */",
    "data _TFL_HSTAT_001;",
    "  length analysis_id group_path node_key runtime_row_id row_role $128;",
    "  set _TFL_HNODE_001;",
    "  /* Nested result_map contributes chunk/row/header/statistic identity. */",
    "run;",
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
