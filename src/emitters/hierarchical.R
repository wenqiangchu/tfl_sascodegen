# Hierarchical source, node-scoped primitive analysis, and ordered report rows.

hierarchical_source_dataset <- function(batch_order) {
  sprintf("_TFL_HNODE_%03d", batch_order)
}

hierarchical_level_dataset <- function(batch_order, level_order) {
  sprintf("_TFL_HLEVEL_%03d_%03d", batch_order, level_order)
}

hierarchical_nodes_dataset <- function(batch_order, level_order) {
  sprintf("_TFL_HNODES_%03d_%03d", batch_order, level_order)
}

hierarchical_display_dataset <- function(batch_order, level_order) {
  sprintf("_TFL_HDISP_%03d_%03d", batch_order, level_order)
}

hierarchical_membership_dataset <- function(batch_order, level_order) {
  sprintf("_TFL_HMERGE_%03d_%03d", batch_order, level_order)
}

hierarchical_text_lengths_source <- function(plan) {
  chunk <- plan$chunks[[1L]]
  suffix <- sprintf("%03d", plan$batch_order)
  c(
    "/* Size node text from SAS WORK descriptors without allocating maximum-length fields per source record. */",
    "data _null_;",
    "  length _tfl_format $64;",
    paste0("  _tfl_dsid = open('_TFL_HSRC_", suffix, "', 'i');"),
    "  _tfl_key_length = 1; _tfl_label_length = &_TFL_LABEL_LEN;",
    "  if _tfl_dsid > 0 then do;",
    unlist(lapply(chunk$levels, function(level) c(
      paste0("    _tfl_varnum = varnum(_tfl_dsid, ", sas_character_literal(level$variable), ");"),
      "    if _tfl_varnum > 0 then do;",
      "      if vartype(_tfl_dsid, _tfl_varnum) = 'C' then _tfl_value_length = varlen(_tfl_dsid, _tfl_varnum) + 2;",
      "      else _tfl_value_length = 18;",
      "    end;",
      "    else _tfl_value_length = 32767;",
      "    _tfl_key_length + _tfl_value_length + 32;",
      paste0("    _tfl_varnum = varnum(_tfl_dsid, ", sas_character_literal(level$label_variable %||% level$variable), ");"),
      "    if _tfl_varnum > 0 then do;",
      "      _tfl_format = varfmt(_tfl_dsid, _tfl_varnum);",
      "      _tfl_format_width = input(compress(scan(_tfl_format, 1, '.'), '0123456789', 'k'), ?? best32.);",
      "      _tfl_label_length = max(_tfl_label_length, varlen(_tfl_dsid, _tfl_varnum), _tfl_format_width, 32);",
      "    end;",
      "    else _tfl_label_length = 32767;"
    )), use.names = FALSE),
    "    _tfl_rc = close(_tfl_dsid);",
    "  end;",
    "  else do; _tfl_key_length = 32767; _tfl_label_length = 32767; end;",
    "  _tfl_key_length = min(32767, _tfl_key_length);",
    "  _tfl_label_length = min(32767, _tfl_label_length);",
    paste0("  call symputx('_TFL_HKEY_LEN_", suffix, "', _tfl_key_length, 'G');"),
    paste0("  call symputx('_TFL_HLABEL_LEN_", suffix, "', _tfl_label_length, 'G');"),
    "  call symputx('_TFL_NODE_LEN', max(&_TFL_NODE_LEN, _tfl_key_length), 'G');",
    "  call symputx('_TFL_LABEL_LEN', max(&_TFL_LABEL_LEN, _tfl_label_length), 'G');",
    "  call symputx('_TFL_RUNTIME_LEN', min(32767, max(&_TFL_RUNTIME_LEN, _tfl_key_length + 2 * &_TFL_ID_LEN + 96)), 'G');",
    "run;"
  )
}

hierarchical_nested_plan <- function(plan, block, block_order, resolved) {
  definition <- chunk_registry_lookup(resolved$registry, block$type)
  if (is.null(definition) || is.null(definition$emitter)) {
    stop("Nested hierarchical primitive emitter is unavailable.", call. = FALSE)
  }
  parent <- plan$chunks[[1L]]
  level_order <- match(block$anchor_level, vapply(parent$levels, function(level) level$id, ""))
  chunk <- block
  chunk$id <- paste0(parent$id, ":", block$id)
  chunk$source_data <- hierarchical_membership_dataset(plan$batch_order, level_order)
  chunk$filter <- NULL
  global_denominator_source <- NULL
  if (!identical(block$type, "continuous_summary")) {
    scope <- block$denominator$scope
    chunk$denominator$type <- switch(scope,
      header_population = "header_population", current_group = "header_population",
      non_missing = "non_missing", custom = "custom"
    )
    if (scope == "header_population" && block$denominator$unit != "distinct_subject") {
      global_denominator_source <- sprintf("_TFL_HSRC_%03d", plan$batch_order)
    }
  }
  batch_order <- as.integer(plan$nested_batch_start + block_order)
  structure(c(list(
    batch_order = batch_order, chunk_type = definition$type_id, chunk_orders = 1L,
    chunks = list(chunk),
    logical_maps = list(chunk_logical_map(chunk, 1L, resolved$header$columns)),
    result_map = build_logical_result_map(chunk, 1L, resolved$header$columns, analysis_id = block$id),
    header_columns = resolved$header$columns,
    header_columns_dataset = plan$header_columns_dataset,
    membership_dataset = sprintf("_TFL_HMEM_%03d", plan$batch_order),
    membership_expanded_source = TRUE,
    subject_key = parent$source_contract$subject_key,
    nodes_dataset = hierarchical_nodes_dataset(plan$batch_order, level_order),
    global_denominator_source = global_denominator_source,
    include_duplicate_check = isTRUE(plan$include_duplicate_check),
    grouping_variables = "node_key", definition = definition
  ), batch_dataset_names(definition, batch_order)), class = c("PrimitiveBatchPlan", "list"))
}

hierarchical_membership_source <- function(plan, level_order) {
  suffix <- sprintf("%03d", plan$batch_order)
  subject_key <- plan$chunks[[1L]]$source_contract$subject_key
  c(
    paste0("/* Expand hierarchical level ", level_order,
           " records through header membership once for all anchored blocks. */"),
    "proc sql noprint;",
    paste0("  create table ", hierarchical_membership_dataset(plan$batch_order, level_order), " as"),
    "  select m.USUBJID, m.header_column_id, m.column_order, s.*",
    paste0("  from _TFL_HMEM_", suffix, " as m inner join"),
    paste0("    ", hierarchical_level_dataset(plan$batch_order, level_order),
           "(rename=(", subject_key, "=_TFL_SOURCE_SUBJECT)) as s"),
    "  on m.USUBJID = s._TFL_SOURCE_SUBJECT;",
    "quit;"
  )
}

hierarchical_level_source <- function(plan, level_order) {
  chunk <- plan$chunks[[1L]]
  level <- chunk$levels[[level_order]]
  suffix <- sprintf("%03d_%03d", plan$batch_order, level_order)
  input <- if (level_order == 1L) hierarchical_source_dataset(plan$batch_order) else
    hierarchical_level_dataset(plan$batch_order, level_order - 1L)
  assigned <- hierarchical_level_dataset(plan$batch_order, level_order)
  nodes <- hierarchical_nodes_dataset(plan$batch_order, level_order)
  ordered_variable <- paste0(if (identical(level$order_direction, "desc")) "descending " else "",
                             level$order_variable)
  by_vars <- paste(c("parent_node_key", ordered_variable,
                     if (!identical(level$variable, level$order_variable)) level$variable), collapse = " ")
  c(
    paste0("/* Discover hierarchical level ", level_order, " nodes. */"),
    paste0("data _TFL_HVALUE_", suffix, ";"),
    paste0("  length node_key group_path level_value level_component parent_node_key $&_TFL_HKEY_LEN_", sprintf("%03d", plan$batch_order), ";"),
    paste0("  length node_order_path parent_order_path $", length(chunk$levels) * 11L,
           " node_label $&_TFL_HLABEL_LEN_", sprintf("%03d", plan$batch_order), ";"),
    paste0("  set ", input, ";"),
    if (level_order == 1L) c("  parent_node_key = '';", "  parent_order_path = '';") else
      c("  parent_node_key = node_key;", "  parent_order_path = node_order_path;"),
    if (identical(level$missing_policy, "exclude"))
      paste0("  if missing(", level$variable, ") then delete;"),
    if (identical(level$missing_policy, "error")) c(
      paste0("  if missing(", level$variable, ") then do;"),
      "    putlog 'WARNING: [USER] missing_level'; delete;",
      "  end;"
    ),
    paste0("  if vtype(", level$variable, ") = 'N' then level_value = cats('N:', putn(",
           level$variable, ", 'hex16.'));"),
    paste0("  else level_value = 'C:' || ", level$variable, ";"),
    "  level_component = cats(lengthn(level_value), ':', trim(level_value));",
    "  group_path = catt(parent_node_key, level_component);",
    "  node_key = group_path;",
    paste0("  node_label = vvalue(", level$label_variable %||% level$variable, ");"),
    if (identical(level$missing_policy, "label"))
      paste0("  if missing(", level$variable, ") then node_label = ",
             sas_character_literal(level$missing_label), ";"),
    paste0("  hierarchy_level = ", level_order, ";"),
    "run;",
    paste0("proc sort data=_TFL_HVALUE_", suffix, " out=_TFL_HSORT_", suffix, ";"),
    paste0("  by ", by_vars, ";"),
    "run;",
    paste0("data ", assigned, " ", nodes,
           "(keep=node_key group_path node_label node_order_path hierarchy_level parent_node_key);"),
    paste0("  set _TFL_HSORT_", suffix, ";"),
    paste0("  by ", by_vars, ";"),
    "  retain sibling_order;",
    "  if first.parent_node_key then sibling_order = 0;",
    paste0("  if first.", level$variable, " then sibling_order + 1;"),
    "  node_order_path = cats(parent_order_path, 'C', put(sibling_order, z10.));",
    paste0("  output ", assigned, ";"),
    paste0("  if first.", level$variable, " then output ", nodes, ";"),
    "run;"
  )
}

hierarchical_display_order_source <- function(plan, level_order, nested_outputs) {
  chunk <- plan$chunks[[1L]]
  level <- chunk$levels[[level_order]]
  suffix <- sprintf("%03d_%03d", plan$batch_order, level_order)
  nodes <- hierarchical_nodes_dataset(plan$batch_order, level_order)
  sort <- level$result_sort
  metric_fields <- character()
  joins <- character()
  sort_fields <- character()
  if (!is.null(sort)) {
    block_index <- match(sort$metric$analysis_id, vapply(chunk$analysis_blocks, function(block) block$id, ""))
    statistic_dataset <- nested_outputs[[block_index]]$statistic_dataset
    positive_columns <- sort$column_order[sort$column_order > 0L]
    for (index in seq_along(positive_columns)) {
      alias <- paste0("m", index)
      metric_fields <- c(metric_fields,
        paste0("case when ", alias, ".estimable = 1 then ", alias, ".value else . end as metric_", index),
        paste0("case when ", alias, ".estimable = 1 and not missing(", alias,
               ".value) then 0 else 1 end as metric_missing_", index))
      joins <- c(joins, paste0("  left join ", statistic_dataset, " as ", alias,
        " on n.node_key = ", alias, ".node_key and ", alias, ".row_id = ",
        sas_character_literal(sort$metric$row_id), " and ", alias, ".statistic_id = ",
        sas_character_literal(sort$metric$statistic_id), " and ", alias, ".column_order = ",
        positive_columns[[index]]))
      sort_fields <- c(sort_fields, paste0("metric_missing_", index),
                       paste0(if (sort$direction == "desc") "descending " else "", "metric_", index))
    }
    if (0L %in% sort$column_order) {
      metric_fields <- c(metric_fields, "upcase(n.node_label) as label_sort")
      sort_fields <- c(sort_fields, "label_sort")
    }
  }
  parent_dataset <- if (level_order > 1L) hierarchical_display_dataset(plan$batch_order, level_order - 1L) else NULL
  c(
    "/* Resolve node display order after raw statistics, keeping missing metrics last. */",
    "proc sql noprint;",
    paste0("  create table _TFL_HORDER_", suffix, " as"),
    paste0("  select n.*", if (length(metric_fields)) paste0(", ", paste(metric_fields, collapse = ", ")),
           if (!is.null(parent_dataset)) ", p.node_order_path as display_parent_path" else
             paste0(", '' as display_parent_path length=", length(chunk$levels) * 11L)),
    paste0("  from ", nodes, " as n"),
    joins,
    if (!is.null(parent_dataset)) paste0("  left join ", parent_dataset,
                                        " as p on n.parent_node_key = p.node_key"),
    "  ;",
    "quit;",
    paste0("proc sort data=_TFL_HORDER_", suffix, ";"),
    paste0("  by ", paste(c("parent_node_key", sort_fields, "node_order_path"), collapse = " "), ";"),
    "run;",
    paste0("data ", hierarchical_display_dataset(plan$batch_order, level_order), ";"),
    paste0("  set _TFL_HORDER_", suffix, ";"),
    "  by parent_node_key;",
    "  retain sibling_order;",
    "  if first.parent_node_key then sibling_order = 0;",
    "  sibling_order + 1;",
    "  node_order_path = cats(display_parent_path, 'C', put(sibling_order, z10.));",
    "  keep node_key group_path node_label hierarchy_level parent_node_key node_order_path;",
    "run;"
  )
}

hierarchical_label_rows_source <- function(plan, level_order) {
  chunk <- plan$chunks[[1L]]
  level <- chunk$levels[[level_order]]
  suffix <- sprintf("%03d_%03d", plan$batch_order, level_order)
  c(
    "/* Materialize dynamic node labels once for every displayed header column. */",
    paste0("data _TFL_HLABEL_", suffix, ";"),
    "  length chunk_id row_id header_column_id $&_TFL_ID_LEN label $&_TFL_LABEL_LEN cell_text $&_TFL_CELL_LEN;",
    paste0("  length runtime_row_id $&_TFL_RUNTIME_LEN order_key $", length(chunk$levels) * 11L + 21L, " row_role $16;"),
    paste0("  set ", hierarchical_display_dataset(plan$batch_order, level_order), ";"),
    paste0("  chunk_id = ", sas_character_literal(chunk$id), ";"),
    paste0("  row_id = ", sas_character_literal(level$id), ";"),
    paste0("  chunk_order = ", plan$chunk_orders[[1L]], ";"),
    "  label = node_label; cell_text = ''; row_role = 'dynamic';",
    paste0("  indent_level = ", level_order - 1L, ";"),
    "  runtime_row_id = cats(lengthn(node_key), ':', node_key, ':label');",
    "  order_key = cats(node_order_path, 'A');",
    unlist(lapply(seq_along(plan$header_columns), function(index) {
      paste0("  column_order = ", index, "; header_column_id = ",
             sas_character_literal(plan$header_columns[[index]]$id), "; output;")
    }), use.names = FALSE),
    "run;"
  )
}

hierarchical_block_rows_source <- function(plan, block_order, nested_output) {
  chunk <- plan$chunks[[1L]]
  block <- chunk$analysis_blocks[[block_order]]
  level_order <- match(block$anchor_level, vapply(chunk$levels, function(level) level$id, ""))
  suffix <- sprintf("%03d_%03d", plan$batch_order, block_order)
  same_row <- identical(block$placement, "same_row")
  c(
    "/* Overlay hierarchical identity fields on nested long-form rows. */",
    "proc sql noprint;",
    paste0("  create table _TFL_HRJOIN_", suffix, " as"),
    "  select r.*, n.node_order_path as display_order_path",
    paste0("  from ", nested_output$render_dataset, " as r left join ",
           hierarchical_display_dataset(plan$batch_order, level_order), " as n"),
    "    on r.node_key = n.node_key;",
    "quit;",
    paste0("data _TFL_HMAP_", suffix, ";"),
    paste0("  length analysis_id $&_TFL_ID_LEN runtime_row_id $&_TFL_RUNTIME_LEN order_key $",
           length(chunk$levels) * 11L + 21L, " row_role $16;"),
    paste0("  set _TFL_HRJOIN_", suffix, ";"),
    paste0("  chunk_id = ", sas_character_literal(chunk$id), ";"),
    paste0("  chunk_order = ", plan$chunk_orders[[1L]], ";"),
    paste0("  analysis_id = ", sas_character_literal(block$id), ";"),
    paste0("  block_order = ", block_order, ";"),
    "  runtime_row_id = cats(lengthn(node_key), ':', node_key,",
    "    lengthn(analysis_id), ':', analysis_id, lengthn(row_id), ':', row_id);",
    if (same_row) c(
      "  label = node_label; row_role = 'dynamic';",
      paste0("  indent_level = ", level_order - 1L, ";"),
      "  order_key = cats(display_order_path, 'A');"
    ) else c(
      "  row_role = 'static';",
      paste0("  indent_level = ", level_order, " + indent_level;"),
      "  order_key = cats(display_order_path, 'B', put(block_order, z10.), put(row_order, z10.));"
    ),
    "run;"
  )
}

hierarchical_continuous_compatibility <- function(plan, nested) {
  # Only the built-in emitter exposes the preparation/MEANS/result contract.
  # Alternative registered emitters retain their own complete source path.
  if (!identical(nested$chunk_type, "continuous_summary") ||
      !identical(nested$definition$emitter, continuous_summary_emitter) ||
      !isTRUE(nested$definition$batch_contract$batchable)) return(NULL)
  block <- nested$chunks[[1L]]
  list(
    primitive_type = nested$chunk_type,
    source_contract = plan$chunks[[1L]]$source_contract,
    membership_source = block$source_data,
    nodes_dataset = nested$nodes_dataset,
    counting_unit = block$counting_unit,
    distinct_key = block$distinct_key,
    primitive_definition = nested$definition
  )
}

hierarchical_nested_groups <- function(plan, nested_plans) {
  groups <- list()
  chunk <- plan$chunks[[1L]]
  level_ids <- vapply(chunk$levels, function(level) level$id, "")
  for (index in seq_along(nested_plans)) {
    nested <- nested_plans[[index]]
    block <- chunk$analysis_blocks[[index]]
    compatibility <- hierarchical_continuous_compatibility(plan, nested)
    member <- list(
      block_order = index, analysis_id = block$id, primitive_plan = nested,
      analysis_input_dataset = if (!is.null(compatibility)) {
        if (identical(block$counting_unit, "record")) nested$input_dataset else
          continuous_counting_unit_dataset(nested$batch_order)
      } else NULL
    )
    last <- length(groups)
    if (last > 0L && !is.null(compatibility) &&
        identical(groups[[last]]$compatibility, compatibility)) {
      groups[[last]]$members <- c(groups[[last]]$members, list(member))
    } else {
      suffix <- sprintf("%03d_%03d", plan$batch_order, index)
      groups[[last + 1L]] <- list(
        container_order = plan$batch_order,
        anchor_level_order = match(block$anchor_level, level_ids),
        compatibility = compatibility, members = list(member),
        input_dataset = paste0("_TFL_HCIN_", suffix),
        raw_dataset = paste0("_TFL_HCRAW_", suffix)
      )
    }
  }
  groups
}

hierarchical_shared_means_source <- function(group) {
  # SET sees only numeric values and the common node key, never typed unit keys.
  inputs <- vapply(group$members, function(member) {
    paste0("    ", member$analysis_input_dataset,
           "(keep=node_key column_order analysis_value in=_tfl_member_",
           member$block_order, ")")
  }, "")
  assignments <- vapply(group$members, function(member) {
    paste0("  if _tfl_member_", member$block_order,
           " then analysis_order = ", member$block_order, ";")
  }, "")
  raw_outputs <- vapply(group$members, function(member) member$primitive_plan$raw_dataset, "")
  routes <- vapply(group$members, function(member) {
    paste0("  if analysis_order = ", member$block_order,
           " then output ", member$primitive_plan$raw_dataset, ";")
  }, "")
  c(
    "/* Combine prepared continuous values while preserving each block identity. */",
    paste0("data ", group$input_dataset, ";"),
    "  length analysis_order column_order analysis_value 8 node_key $&_TFL_NODE_LEN;",
    "  set", inputs, "  ;", assignments,
    "  keep analysis_order node_key column_order analysis_value;",
    "run;",
    continuous_means_source(group$input_dataset, group$raw_dataset,
                            c("analysis_order", "column_order", "node_key")),
    "/* Restore each block's private raw output before expected-cell completion. */",
    paste0("data ", paste(raw_outputs, collapse = " "), ";"),
    paste0("  set ", group$raw_dataset, ";"),
    "  chunk_order = 1;",
    "  drop analysis_order;",
    routes,
    "run;"
  )
}

hierarchical_shared_statistic_source <- function(group) {
  outputs <- vapply(group$members, function(member) member$primitive_plan$statistic_dataset, "")
  inputs <- vapply(group$members, function(member) {
    batch <- member$primitive_plan$batch_order
    sprintf("_TFL_CJOIN_%03d(in=_tfl_result_%03d)", batch, batch)
  }, "")
  input_lines <- paste0(c("  set ", rep("      ", length(inputs) - 1L)), inputs)
  input_lines[[length(input_lines)]] <- paste0(tail(input_lines, 1L), ";")
  routes <- vapply(group$members, function(member) {
    paste0(sprintf("  if _tfl_result_%03d", member$primitive_plan$batch_order),
           " then output ", member$primitive_plan$statistic_dataset, ";")
  }, "")
  declaration <- paste0("data ", paste(outputs, collapse = " "), ";")
  # Keep large output lists readable without hiding names behind a macro.
  if (nchar(declaration) > 80L) declaration <- c("data", paste0("  ", outputs), "  ;")
  c(
    "/* Apply the same statistic conversion to each block's prepared results. */",
    declaration, input_lines,
    continuous_statistic_value_source(),
    routes, "run;"
  )
}

hierarchical_nested_analysis <- function(plan, nested_plans, resolved) {
  groups <- hierarchical_nested_groups(plan, nested_plans)
  outputs <- vector("list", length(nested_plans))
  source <- character()
  chunk <- plan$chunks[[1L]]
  for (group in groups) {
    shared <- length(group$members) > 1L
    for (member in group$members) {
      index <- member$block_order
      block <- chunk$analysis_blocks[[index]]
      nested <- member$primitive_plan
      source <- c(source,
        paste0("/* Execute nested primitive analysis for node scope ", block$id, ". */"),
        paste0("/* Nested primitive type: ", block$type, "; anchor level: ", block$anchor_level, ". */")
      )
      if (shared) {
        prepared <- continuous_batch_preparation(nested)
        source <- c(source,
          continuous_chunk_source(nested, list(chunk_order = 1L, chunk = nested$chunks[[1L]])),
          prepared$source
        )
        outputs[[index]] <- new_emitter_output(list(), nested$statistic_dataset, nested$render_dataset)
      } else {
        outputs[[index]] <- nested$definition$emitter(nested, resolved)
        source <- c(source, vapply(outputs[[index]]$sections, function(section) section$text, ""))
      }
    }
    if (shared) {
      source <- c(source, hierarchical_shared_means_source(group))
      for (member in group$members) {
        source <- c(source,
          expected_cell_skeleton_source(member$primitive_plan),
          continuous_statistic_join_source(member$primitive_plan)
        )
      }
      source <- c(source, hierarchical_shared_statistic_source(group))
    }
    for (member in group$members) {
      index <- member$block_order
      source <- c(source,
        if (shared) render_long_form_source(member$primitive_plan),
        paste0("data _TFL_HSMAP_", sprintf("%03d_%03d", plan$batch_order, index), ";"),
        "  length analysis_id $&_TFL_ID_LEN;",
        paste0("  set ", outputs[[index]]$statistic_dataset, ";"),
        paste0("  chunk_id = ", sas_character_literal(chunk$id), ";"),
        paste0("  analysis_id = ", sas_character_literal(member$analysis_id), ";"),
        "run;"
      )
    }
  }
  list(source = source, outputs = outputs)
}

hierarchical_summary_emitter <- function(plan, resolved) {
  if (!inherits(plan, "PrimitiveBatchPlan") ||
      !identical(plan$chunk_type, "hierarchical_summary") || length(plan$chunks) != 1L) {
    stop("Hierarchical emitter received an incompatible batch plan.", call. = FALSE)
  }
  chunk <- plan$chunks[[1L]]
  batch <- plan$batch_order
  suffix <- sprintf("%03d", batch)
  source <- paste0("_TFL_HSRC_", suffix)
  keys <- if (chunk$source_contract$grain == "subject") chunk$source_contract$subject_key else chunk$source_contract$record_key
  hierarchical_dedup <- if (isTRUE(plan$auto_dedup)) {
    source_auto_dedup_guard(source, keys, paste0("H", suffix))
  } else {
    list(source = character(), dataset = source)
  }
  nested_plans <- lapply(seq_along(chunk$analysis_blocks), function(index) {
    nested <- hierarchical_nested_plan(plan, chunk$analysis_blocks[[index]], index, resolved)
    # A global denominator must be read from the deduplicated container source so
    # it matches the records that drive nodes and rows.
    if (isTRUE(plan$auto_dedup) &&
        identical(nested$global_denominator_source, source)) {
      nested$global_denominator_source <- hierarchical_dedup$dataset
    }
    nested
  })
  nested_analysis <- hierarchical_nested_analysis(plan, nested_plans, resolved)
  nested_outputs <- nested_analysis$outputs
  anchored_levels <- unique(vapply(chunk$analysis_blocks, function(block) {
    match(block$anchor_level, vapply(chunk$levels, function(level) level$id, ""))
  }, integer(1L)))
  membership_sources <- unlist(lapply(anchored_levels, function(level_order) {
    hierarchical_membership_source(plan, level_order)
  }), use.names = FALSE)
  display_sources <- unlist(lapply(seq_along(chunk$levels), function(index) {
    hierarchical_display_order_source(plan, index, nested_outputs)
  }), use.names = FALSE)
  row_sources <- character()
  row_datasets <- character()
  for (index in seq_along(chunk$levels)) {
    if (identical(chunk$levels[[index]]$node_role, "label")) {
      row_sources <- c(row_sources, hierarchical_label_rows_source(plan, index))
      row_datasets <- c(row_datasets, sprintf("_TFL_HLABEL_%03d_%03d", batch, index))
    }
  }
  for (index in seq_along(chunk$analysis_blocks)) {
    block <- chunk$analysis_blocks[[index]]
    level <- chunk$levels[[match(block$anchor_level, vapply(chunk$levels, function(x) x$id, ""))]]
    if (identical(block$placement, "same_row") &&
        (!identical(level$node_role, "analysis") || !identical(level$node_analysis_id, block$id))) next
    row_sources <- c(row_sources, hierarchical_block_rows_source(plan, index, nested_outputs[[index]]))
    row_datasets <- c(row_datasets, sprintf("_TFL_HMAP_%03d_%03d", batch, index))
  }
  text <- c(
    "/* Filter and guard hierarchical source before level discovery. */",
    paste0("data ", source, ";"),
    paste0("  set ", chunk$source_data, ";"),
    if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;"),
    "  source_row = _n_;",
    "run;",
    hierarchical_text_lengths_source(plan),
    # Deduplication runs before the guard and before level discovery so the
    # retained source is what drives nodes, rows, and counting units.
    hierarchical_dedup$source,
    if (isTRUE(plan$include_duplicate_check))
      source_duplicate_guard(hierarchical_dedup$dataset, keys, paste0("H", suffix)),
    "/* Discover nodes across the union of the displayed population columns. */",
    "proc sql noprint;",
    paste0("  create table ", hierarchical_source_dataset(batch), " as"),
    paste0("  select s.* from ", hierarchical_dedup$dataset, " as s where exists"),
    paste0("    (select 1 from _TFL_MEM_001 as m where m.USUBJID = s.",
           chunk$source_contract$subject_key, ");"),
    "quit;",
    paste0("data _TFL_HMEM_", suffix, ";"),
    "  set _TFL_MEM_001;",
    "run;",
    unlist(lapply(seq_along(chunk$levels), function(index) hierarchical_level_source(plan, index)), use.names = FALSE),
    membership_sources,
    nested_analysis$source,
    "/* Map nested primitive results to hierarchical identities. */",
    paste0("data ", plan$statistic_dataset, ";"),
    paste0("  set ", paste(sprintf("_TFL_HSMAP_%03d_%03d", batch, seq_along(nested_outputs)), collapse = " "), ";"),
    "run;",
    display_sources,
    "/* Order current node and below static rows before dynamic children. */",
    row_sources,
    paste0("data _TFL_HROWS_", suffix, ";"),
    paste0("  set ", paste(row_datasets, collapse = " "), ";"),
    "run;",
    paste0("proc sort data=_TFL_HROWS_", suffix, " out=_TFL_HFLAT_", suffix, ";"),
    "  by order_key column_order;",
    "run;",
    paste0("data ", plan$render_dataset, ";"),
    "  /* Discard block-local counters before assigning container-wide row numbers. */",
    paste0("  set _TFL_HFLAT_", suffix, "(drop=row_sequence);"),
    "  by order_key;",
    "  retain row_sequence 0;",
    "  if first.order_key then row_sequence + 1;",
    "  keep chunk_id row_id label indent_level header_column_id cell_text",
    "    chunk_order row_sequence column_order runtime_row_id row_role hierarchy_level node_key;",
    "run;"
  )
  new_emitter_output(list(new_source_section(
    paste0("hierarchical_", batch), "hierarchical", chunk$id, 100L, paste(text, collapse = "\n")
  )), plan$statistic_dataset, plan$render_dataset)
}
