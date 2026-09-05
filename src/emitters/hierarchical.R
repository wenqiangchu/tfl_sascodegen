# Source emitter for hierarchical containers. Containers are never cross-batched.

hierarchical_source_dataset <- function(batch_order) {
  paste0("_TFL_HNODE_", sprintf("%03d", batch_order))
}

hierarchical_nested_plan <- function(plan, block, block_order, resolved) {
  definition <- chunk_registry_lookup(resolved$registry, block$type)
  if (is.null(definition) || is.null(definition$emitter)) {
    stop("Nested hierarchical primitive emitter is unavailable.", call. = FALSE)
  }
  chunk <- block
  chunk$id <- paste0(plan$chunks[[1L]]$id, "_", block$id)
  chunk$source_data <- hierarchical_source_dataset(plan$batch_order)
  chunk$filter <- plan$chunks[[1L]]$filter %||% NULL
  structure(list(
    batch_order = as.integer(plan$batch_order * 100L + block_order),
    chunk_type = definition$type_id,
    chunk_orders = 1L,
    chunks = list(chunk),
    logical_maps = list(chunk_logical_map(chunk, 1L, resolved$header$columns)),
    result_map = build_logical_result_map(chunk, 1L, resolved$header$columns,
                                          analysis_id = block$id),
    header_columns = resolved$header$columns,
    membership_dataset = paste0("_TFL_HMEM_", sprintf("%03d", plan$batch_order)),
    grouping_variables = "node_key",
    definition = definition,
    input_dataset = paste0("_TFL_HIN_", sprintf("%03d", block_order)),
    raw_dataset = paste0("_TFL_HRAW_", sprintf("%03d", block_order)),
    precision_dataset = paste0("_TFL_HPREC_", sprintf("%03d", block_order)),
    statistic_dataset = paste0("_TFL_HNSTAT_", sprintf("%03d", block_order)),
    render_dataset = paste0("_TFL_HNREND_", sprintf("%03d", block_order))
  ), class = c("PrimitiveBatchPlan", "list"))
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
      paste0("proc sort data=", if (index == 1L) node_dataset else
               paste0("_TFL_HLEVEL_", sprintf("%03d", index - 1L)),
             " out=_TFL_HLEVEL_",
             sprintf("%03d", index), ";"),
      paste0("  by ", level$order_variable, ";"),
      "run;",
      paste0("data _TFL_HLEVEL_", sprintf("%03d", index), ";"),
      paste0("  set _TFL_HLEVEL_", sprintf("%03d", index), ";"),
      if (index > 1L) "  parent_node_key = coalescec(parent_node_key, node_key);" else character(),
      paste0("  level_component = cats(lengthn(strip(", level$variable, ")), ':', strip(", level$variable, "));"),
      if (index == 1L) "  group_path = level_component;" else
        c("  parent_node_key = node_key;",
          "  group_path = cats(parent_node_key, '|', level_component);"),
      "  node_key = group_path;",
      if (index > 1L) "  parent_node_key = substr(group_path, 1, lengthn(parent_node_key));" else character(),
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
      paste0("/* Nested primitive type: ", block$type, "; anchor level: ", block$anchor_level, ". */"),
      paste0("analysis_id = ", sas_character_literal(block$id), ";"),
      paste0("anchor_level = ", sas_character_literal(block$anchor_level), ";"),
      paste0("placement = ", sas_character_literal(block$placement), ";"),
      paste0("runtime_row_id = cats(node_key, ':', analysis_id);"),
      paste0("block_order = ", index, ";"),
      "row_order = 0;",
      "row_role = 'static';"
    )
  }), use.names = FALSE)
  nested_sections <- list()
  nested_datasets <- character()
  for (index in seq_along(chunk$analysis_blocks)) {
    nested_plan <- hierarchical_nested_plan(plan, chunk$analysis_blocks[[index]], index, resolved)
    nested_output <- nested_plan$definition$emitter(nested_plan, resolved)
    nested_sections <- c(nested_sections, list(new_source_section(
      paste0("hierarchical_nested_", index), "nested", chunk$analysis_blocks[[index]]$id,
      50L + index, paste(c(
        paste0("/* Execute nested primitive analysis for node scope ", chunk$analysis_blocks[[index]]$id, ". */"),
        vapply(nested_output$sections, `[[`, "", "text")
      ), collapse = "\n")
    )))
    nested_datasets <- c(nested_datasets, nested_output$render_dataset)
  }
  nested_set <- if (length(nested_datasets) > 0L) paste(nested_datasets, collapse = " ") else node_dataset
  membership_dataset <- paste0("_TFL_HMEM_", sprintf("%03d", plan$batch_order))
  text <- c(
    "/* Filter and guard hierarchical source before level discovery. */",
    paste0("data ", node_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;") else character(),
    "run;",
    "/* Restrict nested primitive analyses to the current hierarchical node scope. */",
    paste0("proc sort data=", node_dataset, " out=", membership_dataset, " nodupkey;"),
    "  by USUBJID;",
    "run;",
    paste0("data ", membership_dataset, ";"),
    paste0("  set ", membership_dataset, ";"),
    "  keep USUBJID;",
    "run;",
    duplicate_guard,
    level_lines,
    if (length(chunk$levels) > 0L) c(
      "/* Materialize the deepest parent-child node paths for nested analyses. */",
      paste0("data ", node_dataset, ";"),
      paste0("  set _TFL_HLEVEL_", sprintf("%03d", length(chunk$levels)), ";"),
      "run;"
    ) else character(),
    "/* Order static rows before dynamic children and preserve result sort metadata. */",
    block_lines,
    vapply(nested_sections, `[[`, "", "text"),
    "/* Map nested primitive results to hierarchical identities. */",
    paste0("data _TFL_HSTAT_", sprintf("%03d", plan$batch_order), ";"),
    "  length analysis_id group_path node_key runtime_row_id row_role $128;",
    paste0("  set ", nested_set, ";"),
    "  /* Nested result_map contributes chunk/row/header/statistic identity. */",
    "  analysis_id = coalescec(analysis_id, '');",
    "  runtime_row_id = cats(node_key, ':', analysis_id, ':', row_id);",
    "  group_path = coalescec(group_path, node_key, '');",
    "  node_key = coalescec(node_key, group_path, '');",
    "  /* Static rows sort before dynamic children at the same node. */",
    "  sort_key = cats(group_path, '|', putn(0, 'Z6.'), '|', runtime_row_id);",
    "run;",
    "/* Flatten current node, below static rows, then dynamic children. */",
    paste0("proc sort data=_TFL_HSTAT_", sprintf("%03d", plan$batch_order),
           " out=_TFL_HFLAT_", sprintf("%03d", plan$batch_order), ";"),
    "  by group_path row_role block_order row_order sort_key;",
    "run;",
    paste0("data ", plan$render_dataset, ";"),
    "  length chunk_id row_id label indent_level header_column_id cell_text $256;",
    paste0("  set _TFL_HFLAT_", sprintf("%03d", plan$batch_order), ";"),
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
