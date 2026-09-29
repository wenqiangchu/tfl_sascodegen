metadata_editor_server_impl <- function(input, output, session) {
  editor_state <- new_metadata_editor_state()
  workspace <- editor_state$workspace
  metadata_loaded <- editor_state$metadata_loaded
  active_editor <- editor_state$active_editor
  active_draft <- editor_state$active_draft
  pending_action <- editor_state$pending_action
  pending_seed <- editor_state$pending_seed
  header_table <- editor_state$header_table
  template_value <- editor_state$template_value
  row_table_cache <- editor_state$row_table_cache
  statistic_table_cache <- editor_state$statistic_table_cache
  status <- editor_state$status
  source_text <- editor_state$source_text
  generated_table_id <- editor_state$generated_table_id
  sas_download_ready <- editor_state$sas_download_ready
  suppress_navigation <- editor_state$suppress_navigation

  editor_id <- function() (active_editor() %||% list())$document_id %||% ""
  editor_type <- function() (active_editor() %||% list())$document_type %||% ""
  list_ids <- function(type) {
    ids <- vapply(workspace()[[editor_collection_name(type)]] %||% list(), function(x) x$id %||% "", character(1))
    draft <- active_draft()
    if (!is.null(draft) && identical(draft$operation, "create") && identical(draft$target$document_type, type)) {
      ids <- c(ids, draft$target$document_id)
    }
    unique(ids)
  }
  current_base <- function() {
    draft <- active_draft()
    if (is.null(draft)) return(NULL)
    if (identical(draft$operation, "create")) clone_metadata_value(pending_seed()) else clone_metadata_value(draft$original)
  }
  trim_optional <- function(x) { x <- as.character(x %||% ""); if (nzchar(x)) x else NULL }
  split_keys <- function(x) {
    x <- trimws(unlist(strsplit(as.character(x %||% ""), ",", fixed=TRUE)))
    x[nzchar(x)]
  }
  normalize_stat_digits <- function(x) {
    x <- trimws(as.character(x %||% "")); if (!nzchar(x)) return(NULL)
    if (grepl("^[+-][0-9]+$", x)) x else suppressWarnings(as.integer(x))
  }
  collect_rows <- function(rows, prefix) {
    cache_key <- paste0(prefix, "rows")
    cached <- row_table_cache()[[cache_key]]
    if (!is.null(cached)) {
      rows <- lapply(seq_len(nrow(cached)), function(i) {
        z <- as.list(cached[i, , drop = FALSE])
        z$id <- as.character(z$.row_id %||% z$id %||% sprintf("row_%03d", i)); z$.row_id <- NULL
        z$type <- as.character(z$type)
        z$label <- as.character(z$label)
        z$indent_level <- suppressWarnings(as.integer(z$indent_level))
        if (is.na(z$indent_level)) z$indent_level <- 0L
        z$condition <- trim_optional(z$condition)
        z$cell_format <- as.character(z$cell_format %||% "")
        stat_ids <- strsplit(trimws(as.character(z$statistics %||% "")), "\\s+")[[1L]]
        if (!length(stat_ids) || !nzchar(stat_ids[[1L]])) stat_ids <- character()
        digit_tokens <- strsplit(trimws(as.character(z$digits %||% "")), "\\s+")[[1L]]
        if (!length(digit_tokens) || !nzchar(digit_tokens[[1L]])) digit_tokens <- character()
        z$statistics <- lapply(seq_along(stat_ids), function(j) {
          s <- list(id=stat_ids[[j]]); d <- digit_tokens[[j]] %||% "-"
          if (!identical(d, "-") && nzchar(d)) s$digits <- normalize_stat_digits(d)
          s
        })
        z$statistics <- if (z$type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) z$statistics else z$statistics
        z$digits <- NULL; z$statistics_text <- NULL
        z
      })
    }
    rows %||% list()
  }
  collect_template_from_ui <- function(strip_ids = FALSE) {
    value <- clone_metadata_value(template_value() %||% current_base()); if (is.null(value)) return(NULL)
    value$body$stub_header <- as.character(input$template_stub_header %||% value$body$stub_header %||% "")
    chunks <- value$body$chunks %||% list()
    for (i in seq_along(chunks)) {
      chunk <- chunks[[i]]; p <- paste0("chunk_", i, "_")
      chunk$source_data <- as.character(input[[paste0(p,"source_data")]] %||% chunk$source_data %||% "")
      chunk$filter <- trim_optional(input[[paste0(p,"filter")]] %||% chunk$filter)
      if (identical(chunk$type, "continuous_summary")) {
        chunk$analysis_variable <- as.character(input[[paste0(p,"analysis_variable")]] %||% chunk$analysis_variable %||% "")
        chunk$rows <- collect_rows(chunk$rows, p)
      } else if (chunk$type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
        dtype <- as.character(input[[paste0(p,"den_type")]] %||% chunk$denominator$type %||% "header_population")
        den <- list(type=dtype)
        if (identical(dtype,"non_missing")) den$variable <- as.character(input[[paste0(p,"den_variable")]] %||% "")
        if (identical(dtype,"custom")) den$expression <- as.character(input[[paste0(p,"den_expression")]] %||% "")
        chunk$denominator <- den; chunk$rows <- collect_rows(chunk$rows, p)
      } else if (identical(chunk$type,"hierarchical_summary")) {
        chunk$source_contract <- list(
          grain=as.character(input[[paste0(p,"grain")]] %||% chunk$source_contract$grain %||% "record"),
          subject_key=as.character(input[[paste0(p,"subject_key")]] %||% chunk$source_contract$subject_key %||% "USUBJID"),
          duplicate_policy=as.character(input[[paste0(p,"duplicate_policy")]] %||% chunk$source_contract$duplicate_policy %||% "error"))
        keys <- split_keys(input[[paste0(p,"record_key")]] %||% paste(chunk$source_contract$record_key %||% character(), collapse=","))
        if (length(keys)) chunk$source_contract$record_key <- keys
        chunk$levels <- lapply(seq_along(chunk$levels %||% list()), function(j) {
          old <- chunk$levels[[j]]; lp <- paste0(p,"level_",j,"_")
          z <- list(id=old$id,
            variable=as.character(input[[paste0(lp,"variable")]] %||% old$variable %||% ""),
            order_variable=as.character(input[[paste0(lp,"order_variable")]] %||% old$order_variable %||% ""),
            order_direction=as.character(input[[paste0(lp,"order_direction")]] %||% old$order_direction %||% "asc"),
            node_role=as.character(input[[paste0(lp,"node_role")]] %||% old$node_role %||% "label"),
            missing_policy=as.character(input[[paste0(lp,"missing_policy")]] %||% old$missing_policy %||% "exclude"))
          for (field in c("parent_level","label_variable","node_analysis_id","missing_label")) {
            v <- trim_optional(input[[paste0(lp,field)]] %||% old[[field]]); if (!is.null(v)) z[[field]] <- v
          }
          z
        })
        chunk$analysis_blocks <- lapply(seq_along(chunk$analysis_blocks %||% list()), function(b) {
          old <- chunk$analysis_blocks[[b]]; bp <- paste0(p,"block_",b,"_")
          z <- list(id=old$id,
            anchor_level=as.character(input[[paste0(bp,"anchor_level")]] %||% old$anchor_level %||% ""),
            placement=as.character(input[[paste0(bp,"placement")]] %||% old$placement %||% "below"),
            type=as.character(input[[paste0(bp,"type")]] %||% old$type %||% "continuous_summary"),
            counting_unit=as.character(input[[paste0(bp,"counting_unit")]] %||% old$counting_unit %||% "record"))
          keys <- split_keys(input[[paste0(bp,"distinct_key")]] %||% paste(old$distinct_key %||% character(),collapse=",")); if (length(keys)) z$distinct_key <- keys
          if (identical(z$type,"continuous_summary")) z$analysis_variable <- as.character(input[[paste0(bp,"analysis_variable")]] %||% old$analysis_variable %||% "") else {
            scope <- as.character(input[[paste0(bp,"den_scope")]] %||% old$denominator$scope %||% "current_group")
            unit <- as.character(input[[paste0(bp,"den_unit")]] %||% old$denominator$unit %||% "record")
            z$denominator <- list(scope=scope,unit=unit)
            if (identical(scope,"non_missing")) z$denominator$variable <- as.character(input[[paste0(bp,"den_variable")]] %||% "")
            if (identical(scope,"custom")) z$denominator$expression <- as.character(input[[paste0(bp,"den_expression")]] %||% "")
          }
          z$rows <- collect_rows(old$rows, bp); z
        })
      }
      chunks[[i]] <- chunk
    }
    value$body$chunks <- chunks
    if (isTRUE(strip_ids)) strip_template_ui_ids(value) else value
  }
  collect_population_from_ui <- function() {
    value <- current_base(); if (is.null(value)) return(NULL)
    value$label <- as.character(input$population_label %||% "")
    value$expression <- as.character(input$population_expression %||% ""); value
  }
  collect_header_from_ui <- function() {
    value <- current_base(); if (is.null(value)) return(NULL)
    data <- header_table() %||% header_editor_data(value)
    header_from_editor_data(value$id, input$header_source_data, data,
                            input$header_orientation %||% value$orientation, original = value)
  }
  collect_table_from_ui <- function() {
    value <- current_base(); if (is.null(value)) return(NULL)
    value$population_id <- as.character(input$table_population_id %||% "")
    value$header_id <- as.character(input$table_header_id %||% "")
    value$template_id <- as.character(input$table_template_id %||% "")
    custom <- list(); before <- as.character(input$table_custom_before %||% ""); after <- as.character(input$table_custom_after %||% "")
    if (nzchar(before)) custom$before <- before; if (nzchar(after)) custom$after <- after
    value$custom_code <- if (length(custom)) custom else NULL; value
  }
  collect_current_editor_value <- function() switch(editor_type(), population=collect_population_from_ui(),
    header=collect_header_from_ui(), table=collect_table_from_ui(),
    template=collect_template_from_ui(strip_ids = TRUE), NULL)
  draft_status <- function() {
    draft <- active_draft(); if (is.null(draft)) return("none")
    if (identical(draft$operation,"create")) return("create_pending")
    # Inputs are populated asynchronously after an editor switch. Until the
    # rendered editor has supplied its anchor field, do not treat empty input
    # values as user edits.
    ready <- switch(editor_type(), population = !is.null(input$population_label),
                    header = !is.null(input$header_source_data),
                    table = !is.null(input$table_population_id),
                    template = !is.null(input$template_stub_header), TRUE)
    if (!isTRUE(ready)) return("update_clean")
    current <- isolate(collect_current_editor_value())
    equal <- if (identical(editor_type(), "template"))
      workspace_canonical_equal(normalize_compare_value(normalize_template_for_compare(draft$original)), normalize_compare_value(normalize_template_for_compare(current)))
      else workspace_canonical_equal(draft$original,current)
    if (equal) "update_clean" else "update_dirty"
  }
  is_guarded <- function() draft_status() %in% c("update_dirty","create_pending")

  list_proxy <- list(population=DT::dataTableProxy("population_list",session=session),
                     header=DT::dataTableProxy("header_list",session=session),
                     table=DT::dataTableProxy("table_list",session=session),
                     template=DT::dataTableProxy("template_list",session=session))
  select_list_row <- function(type,id) {
    index <- match(id,list_ids(type)); if (!is.na(index)) DT::selectRows(list_proxy[[type]],index) else DT::selectRows(list_proxy[[type]],NULL)
  }
  render_editor <- function(type,id,seed=NULL) {
    value <- seed %||% editor_document(workspace(),type,id); if (is.null(value)) return()
    suppress_navigation(TRUE)
    if (type=="population") { updateTextInput(session,"population_label",value=value$label %||% ""); updateTextAreaInput(session,"population_expression",value=value$expression %||% "") }
    if (type=="header") {
      updateTextInput(session,"header_source_data",value=value$source_data %||% "")
      updateSelectInput(session,"header_orientation",selected=value$orientation %||% "")
      header_table(header_editor_data(value))
    }
    if (type=="table") {
      updateSelectInput(session,"table_population_id",choices=list_ids("population"),selected=value$population_id %||% "")
      updateSelectInput(session,"table_header_id",choices=list_ids("header"),selected=value$header_id %||% "")
      updateSelectInput(session,"table_template_id",choices=list_ids("template"),selected=value$template_id %||% "")
      updateTextAreaInput(session,"table_custom_before",value=value$custom_code$before %||% "")
      updateTextAreaInput(session,"table_custom_after",value=value$custom_code$after %||% "")
    }
    if (type=="template") {
      template_value(decorate_template_ui_ids(clone_metadata_value(value)))
      row_table_cache(list()); statistic_table_cache(list())
      updateTextInput(session,"template_stub_header",value=value$body$stub_header %||% "")
    }
    select_list_row(type,id)
    session$onFlushed(function() suppress_navigation(FALSE),once=TRUE)
  }
  activate_editor <- function(type,id,operation="update",seed=NULL) {
    if (!nzchar(id %||% "")) { active_editor(NULL); active_draft(NULL); pending_seed(NULL); return() }
    original <- if (identical(operation,"update")) editor_document(workspace(),type,id) else NULL
    active_editor(list(panel=type,document_type=type,document_id=id))
    active_draft(list(operation=operation,target=list(document_type=type,document_id=id),original=clone_metadata_value(original)))
    pending_seed(if (identical(operation,"create")) clone_metadata_value(seed) else NULL)
    render_editor(type,id,seed)
  }
  clear_editor <- function() { active_editor(NULL); active_draft(NULL); pending_seed(NULL); header_table(NULL); template_value(NULL); row_table_cache(list()); statistic_table_cache(list()) }
  refresh_lists <- function() {
    ids <- list_ids("table")
    selected <- isolate(input$generate_table) %||% ""
    if (!selected %in% ids) selected <- if (length(ids)) ids[[1L]] else ""
    updateSelectInput(session,"generate_table",choices=ids,selected=selected)
  }
  execute_switch <- function(type,id) { activate_editor(type,id); status(paste("Editing",type,id)) }
  show_guard <- function(action) {
    pending_action(action)
    showModal(modalDialog(title="Unsaved changes", "Discard the current changes to continue?",
      footer=tagList(actionButton("guard_discard","Discard changes"),actionButton("guard_cancel","Cancel")),easyClose=FALSE))
  }
  request_action <- function(action) { if (is_guarded()) show_guard(action) else execute_action(action) }
  discard_active <- function() {
    draft <- active_draft(); editor <- active_editor()
    if (is.null(draft)) return()
    if (identical(draft$operation,"create")) clear_editor() else { render_editor(editor$document_type,editor$document_id,draft$original); active_draft(NULL); active_editor(NULL) }
  }
  execute_action <- function(action) {
    kind <- action$kind
    if (kind=="switch") execute_switch(action$type,action$id)
    else if (kind=="panel") {
      clear_editor(); suppress_navigation(TRUE)
      if (action$main=="metadata") updateTabsetPanel(session,"metadata_panel",selected=action$panel)
      updateTabItems(session,"main_nav",selected=action$main)
      ids <- list_ids(action$panel); if (length(ids)) activate_editor(action$panel,ids[[1L]])
      session$onFlushed(function() suppress_navigation(FALSE),once=TRUE)
    } else if (kind=="new") show_new_dialog(action$type)
    else if (kind=="delete") begin_delete(action$type,action$id)
    else if (kind=="import") editor_context$import_now(action$path)
    else if (kind=="generate") editor_context$generate_now()
  }
  save_active <- function(type) {
    if (!identical(editor_type(),type)) return()
    current <- collect_current_editor_value(); draft <- active_draft()
    if (identical(type, "template")) current <- reindex_template(current)
    result <- if (identical(draft$operation,"create")) workspace_create(workspace(),type,current) else workspace_update(workspace(),workspace_target(type,editor_id()),current)
    if (!result$passed) { status(paste("Save failed:",editor_error_text(result$errors))); showNotification(status(),type="error"); return() }
    workspace(result$workspace); id <- current$id; active_draft(NULL); pending_seed(NULL); template_value(NULL); header_table(NULL); generated_table_id(""); sas_download_ready(FALSE); activate_editor(type,id); refresh_lists(); status(paste(tools::toTitleCase(type),"saved."))
  }

  show_new_dialog <- function(type) {
    pending_action(list(kind="confirm_new",type=type))
    showModal(modalDialog(title=paste("New",tools::toTitleCase(type)),textInput("new_object_id","ID"),
      footer=tagList(actionButton("confirm_new_object","Create"),actionButton("cancel_new_object","Cancel")),easyClose=FALSE))
  }
  begin_delete <- function(type,id) {
    draft <- active_draft()
    if (!is.null(draft) && draft$operation=="create" && editor_id()==id) { clear_editor(); ids<-list_ids(type); if(length(ids)) activate_editor(type,ids[[1L]]); status("New object discarded."); return() }
    impact <- workspace_delete_impact(workspace(),type,id)
    if (!impact$allowed) { showNotification(editor_error_text(impact$errors),type="error"); return() }
    pending_action(list(kind="confirm_delete",target=impact$target,type=type,id=id))
    showModal(modalDialog(title="Confirm delete",paste("Delete",type,id,"?"),footer=tagList(actionButton("cancel_delete","Cancel"),actionButton("confirm_delete","Delete",class="btn-danger")),easyClose=FALSE))
  }
  move_item <- function(items,index,direction) { target<-index+if(direction=="up")-1L else 1L; if(index<1L||index>length(items)||target<1L||target>length(items))return(items); z<-items[[index]];items[[index]]<-items[[target]];items[[target]]<-z;items }
  reindex_template <- function(value) {
    for(i in seq_along(value$body$chunks %||% list())) {
      chunk <- value$body$chunks[[i]]; chunk$id <- sprintf("chunk_%03d",i)
      if(length(chunk$rows %||% list())) for(r in seq_along(chunk$rows)) chunk$rows[[r]]$id <- sprintf("%s_row_%03d",chunk$id,r)
      if (identical(chunk$type,"hierarchical_summary")) {
        levels <- chunk$levels %||% list(); blocks <- chunk$analysis_blocks %||% list()
        old_level_ids <- vapply(levels,function(x)x$id,character(1)); new_level_ids <- sprintf("%s_level_%03d",chunk$id,seq_along(levels)); level_map <- setNames(new_level_ids,old_level_ids)
        old_block_ids <- vapply(blocks,function(x)x$id,character(1)); new_block_ids <- sprintf("%s_analysis_%03d",chunk$id,seq_along(blocks)); block_map <- setNames(new_block_ids,old_block_ids); row_maps <- list()
        for (b in seq_along(blocks)) {
          old_row_ids <- vapply(blocks[[b]]$rows %||% list(),function(x)x$id,character(1)); new_row_ids <- sprintf("%s_row_%03d",new_block_ids[[b]],seq_along(old_row_ids)); row_maps[[old_block_ids[[b]]]] <- setNames(new_row_ids,old_row_ids)
          blocks[[b]]$id <- new_block_ids[[b]]; if(length(old_row_ids)) for(r in seq_along(old_row_ids)) blocks[[b]]$rows[[r]]$id <- new_row_ids[[r]]
          if(!is.null(blocks[[b]]$anchor_level) && blocks[[b]]$anchor_level %in% names(level_map)) blocks[[b]]$anchor_level <- unname(level_map[[blocks[[b]]$anchor_level]])
        }
        for (j in seq_along(levels)) {
          levels[[j]]$id <- new_level_ids[[j]]
          if(!is.null(levels[[j]]$parent_level) && levels[[j]]$parent_level %in% names(level_map)) levels[[j]]$parent_level <- unname(level_map[[levels[[j]]$parent_level]])
          if(!is.null(levels[[j]]$node_analysis_id) && levels[[j]]$node_analysis_id %in% names(block_map)) levels[[j]]$node_analysis_id <- unname(block_map[[levels[[j]]$node_analysis_id]])
          metric <- levels[[j]]$result_sort$metric
          if(!is.null(metric$analysis_id) && metric$analysis_id %in% names(block_map)) { old_analysis <- metric$analysis_id; metric$analysis_id <- unname(block_map[[old_analysis]]); if(!is.null(metric$row_id) && metric$row_id %in% names(row_maps[[old_analysis]])) metric$row_id <- unname(row_maps[[old_analysis]][[metric$row_id]]); levels[[j]]$result_sort$metric <- metric }
        }
        chunk$levels <- levels; chunk$analysis_blocks <- blocks
      }
      value$body$chunks[[i]] <- chunk
    }
    value
  }
  mutate_template <- function(fun) {
    current <- collect_template_from_ui()
    template_value(decorate_template_ui_ids(fun(current)))
    row_table_cache(list()); statistic_table_cache(list())
  }
  rows_table_data <- function(rows) {
    rows <- rows %||% list()
    if (!length(rows)) return(data.frame(type=character(), label=character(), indent_level=integer(), condition=character(), statistics=character(), digits=character(), cell_format=character(), .row_id=character(), stringsAsFactors=FALSE))
    data.frame(
      type=vapply(rows,function(x)x$type %||% "analysis",character(1)),
      label=vapply(rows,function(x)x$label %||% "",character(1)),
      indent_level=vapply(rows,function(x)as.integer(x$indent_level %||% 0L),integer(1)),
      condition=vapply(rows,function(x)x$condition %||% "",character(1)),
      statistics=vapply(rows,function(x)paste(vapply(x$statistics %||% list(),function(s)s$id %||% "",character(1)),collapse=" "),character(1)),
      digits=vapply(rows,function(x)paste(vapply(x$statistics %||% list(),function(s) {
        if (!is.null(s$digits)) return(as.character(s$digits))
        if (identical(s$id, "pct")) return("1")
        "-"
      },character(1)),collapse=" "),character(1)),
      cell_format=vapply(rows,function(x)x$cell_format %||% "",character(1)),
      .row_id=vapply(rows,function(x)x$id %||% "",character(1)),
      stringsAsFactors=FALSE)
  }
  editor_context <- new.env(parent = emptyenv())
  list2env(list(
    input=input, output=output, session=session, workspace=workspace,
    metadata_loaded=metadata_loaded, pending_action=pending_action,
    active_editor=active_editor, select_list_row=select_list_row,
    source_text=source_text, generated_table_id=generated_table_id,
    sas_download_ready=sas_download_ready, status=status,
    is_guarded=is_guarded, show_guard=show_guard, clear_editor=clear_editor,
    refresh_lists=refresh_lists, list_ids=list_ids,
    activate_editor=activate_editor, editor_error_text=editor_error_text,
    request_action=request_action, draft_status=draft_status,
    execute_action=execute_action, template_value=template_value,
    header_table=header_table, row_table_cache=row_table_cache, move_item=move_item,
    mutate_template=mutate_template, rows_table_data=rows_table_data,
    new_chunk_seed=new_chunk_seed
  ), editor_context)
  editor_context$editor_type <- editor_type
  editor_context$editor_id <- editor_id
  editor_context$suppress_navigation <- suppress_navigation
  editor_context$save_active <- save_active
  editor_context$discard_active <- discard_active
  editor_context$show_new_dialog <- show_new_dialog
  editor_context$begin_delete <- begin_delete
  editor_context$editor_type <- editor_type
  editor_context$editor_id <- editor_id
  register_metadata_editor_crud(editor_context)
  register_metadata_editor_id_outputs(editor_context)
  register_metadata_editor_collection_navigation(editor_context)
  register_metadata_editor_header(editor_context)
  register_metadata_editor_template(editor_context)
  register_metadata_editor_import(editor_context)
  register_metadata_editor_generation(editor_context)
}
