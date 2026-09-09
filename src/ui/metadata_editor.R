`%||%` <- function(left, right) if (is.null(left)) right else left

metadata_editor_ui <- function() {
  object_list_box <- function(title, type) {
    box(title = title, width = 4,
        actionButton(paste0(type, "_new"), "New"),
        actionButton(paste0(type, "_delete"), "Delete"),
        DTOutput(paste0(type, "_list")))
  }
  dashboardPage(
    dashboardHeader(title = "SAS Code Generator"),
    dashboardSidebar(
      sidebarMenu(id = "main_nav",
        menuItem("Metadata", tabName = "metadata", icon = icon("database")),
        menuItem("Table Metadata", tabName = "table_metadata", icon = icon("table")),
        menuItem("Template Editor", tabName = "template_editor", icon = icon("file")),
        menuItem("Generate SAS", tabName = "generate_sas", icon = icon("code"))),
      tags$hr(), fileInput("bundle", "Metadata bundle (ZIP)", accept = ".zip"),
      downloadButton("download_bundle", "Download metadata")),
    dashboardBody(
      tabItems(
      tabItem(tabName = "metadata",
        tabsetPanel(id = "metadata_panel",
          tabPanel("Population", value = "population", fluidRow(
            object_list_box("Populations", "population"),
            box(title = "Population metadata", width = 8, status = "primary", solidHeader = TRUE,
              uiOutput("population_id_ui"), textInput("population_label", "Label"),
              textAreaInput("population_expression", "SAS expression", rows = 3),
              actionButton("population_save", "Save"),
              actionButton("population_discard", "Discard changes")))),
          tabPanel("Header", value = "header", fluidRow(
            object_list_box("Headers", "header"),
            box(title = "Header metadata", width = 8, status = "primary", solidHeader = TRUE,
              uiOutput("header_id_ui"), textInput("header_source_data", "Source data"),
              h4("Columns and spanning headers"),
              actionButton("header_column_new", "Add row"),
              actionButton("header_column_delete", "Delete selected row"),
              DTOutput("header_columns_table"), actionButton("header_save", "Save"),
              actionButton("header_discard", "Discard changes")))))),
      tabItem(tabName = "table_metadata", fluidRow(
        object_list_box("Tables", "table"),
        box(title = "Table metadata", width = 8, status = "primary", solidHeader = TRUE,
          uiOutput("table_id_ui"), selectInput("table_population_id", "Population", character()),
          selectInput("table_header_id", "Header", character()),
          selectInput("table_template_id", "Template", character()),
          textAreaInput("table_custom_before", "Custom code before", rows = 4),
          textAreaInput("table_custom_after", "Custom code after", rows = 4),
          actionButton("table_save", "Save"), actionButton("table_discard", "Discard changes")))),
      tabItem(tabName = "template_editor", fluidRow(
        object_list_box("Templates", "template"),
        box(title = "Template metadata", width = 8, status = "primary", solidHeader = TRUE,
          uiOutput("template_id_ui"), textInput("template_stub_header", "Stub header"),
          actionButton("template_save", "Save"), actionButton("template_discard", "Discard changes"),
          actionButton("chunk_add", "Add chunk"), uiOutput("chunk_cards")))),
      tabItem(tabName = "generate_sas",
        box(title = "Generate SAS", width = 12, status = "success", solidHeader = TRUE,
          selectInput("generate_table", "Table", character()),
          actionButton("generate", "Generate SAS", icon = icon("play")),
          downloadButton("download_sas", "Download SAS"),
          verbatimTextOutput("status"), verbatimTextOutput("source")))
      )
    )
  )
}

editor_error_text <- function(errors) {
  if (!length(errors)) return("Operation failed.")
  paste(vapply(errors, function(x) x$message %||% "Operation failed.", character(1L)), collapse = " ")
}

readonly_editor_input <- function(id, label, value) {
  tags$div(class = "form-group", tags$label(`for` = id, label),
           tags$input(id = id, class = "form-control", value = value %||% "", readonly = "readonly"))
}

new_chunk_seed <- function(type) {
  row <- list(
    id = "row_001", type = "analysis", label = "New row",
    statistics = list(list(id = "n")), cell_format = "{n}"
  )
  if (identical(type, "continuous_summary")) {
    return(list(
      id = "chunk_001", type = type, source_data = "adam.adsl",
      analysis_variable = "AVAL", rows = list(row)
    ))
  }
  if (type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
    row$statistics <- list(list(id = "n"), list(id = "pct", digits = 1L))
    return(list(
      id = "chunk_001", type = type, source_data = "adam.adsl",
      denominator = list(type = "header_population"), rows = list(row)
    ))
  }
  level <- list(
    id = "level_001", variable = "SOC", order_variable = "SOC",
    order_direction = "asc", node_role = "label", missing_policy = "exclude"
  )
  block <- list(
    id = "analysis_001", anchor_level = level$id, placement = "below",
    type = "continuous_summary", counting_unit = "record",
    analysis_variable = "AVAL", rows = list(row)
  )
  list(
    id = "chunk_001", type = "hierarchical_summary", source_data = "adam.adsl",
    source_contract = list(
      grain = "record", subject_key = "USUBJID", duplicate_policy = "error"
    ), levels = list(level), analysis_blocks = list(block)
  )
}

decorate_template_ui_ids <- function(value) {
  if (is.null(value) || is.null(value$body)) return(value)
  next_id <- 0L
  allocate <- function(prefix) {
    next_id <<- next_id + 1L
    sprintf("%s_%06d", prefix, next_id)
  }
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$ui_uid <- chunk$ui_uid %||% allocate("chunk")
    if (identical(chunk$type, "hierarchical_summary")) {
      for (j in seq_along(chunk$levels %||% list())) {
        chunk$levels[[j]]$ui_uid <- chunk$levels[[j]]$ui_uid %||% allocate("level")
      }
      for (j in seq_along(chunk$analysis_blocks %||% list())) {
        block <- chunk$analysis_blocks[[j]]
        block$ui_uid <- block$ui_uid %||% allocate("analysis")
        chunk$analysis_blocks[[j]] <- block
      }
    }
    value$body$chunks[[i]] <- chunk
  }
  value
}

strip_template_ui_ids <- function(value) {
  if (is.null(value) || is.null(value$body)) return(value)
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$ui_uid <- NULL
    for (j in seq_along(chunk$levels %||% list())) chunk$levels[[j]]$ui_uid <- NULL
    for (j in seq_along(chunk$analysis_blocks %||% list())) chunk$analysis_blocks[[j]]$ui_uid <- NULL
    value$body$chunks[[i]] <- chunk
  }
  value
}

normalize_template_for_compare <- function(value) {
  value <- strip_template_ui_ids(clone_metadata_value(value))
  if (is.null(value) || is.null(value$body)) return(value)
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$id <- NULL
    for (j in seq_along(chunk$rows %||% list())) chunk$rows[[j]]$id <- NULL
    level_ids <- vapply(chunk$levels %||% list(), function(x) x$id %||% "", character(1))
    for (j in seq_along(chunk$levels %||% list())) {
      level <- chunk$levels[[j]]; level$id <- NULL
      level$parent_level <- if (!is.null(level$parent_level)) match(level$parent_level, level_ids) else NULL
      chunk$levels[[j]] <- level
    }
    block_ids <- vapply(chunk$analysis_blocks %||% list(), function(x) x$id %||% "", character(1))
    for (j in seq_along(chunk$analysis_blocks %||% list())) {
      block <- chunk$analysis_blocks[[j]]; block$id <- NULL
      block$anchor_level <- if (!is.null(block$anchor_level)) match(block$anchor_level, level_ids) else NULL
      for (k in seq_along(block$rows %||% list())) block$rows[[k]]$id <- NULL
      chunk$analysis_blocks[[j]] <- block
    }
    value$body$chunks[[i]] <- chunk
  }
  value
}

normalize_compare_value <- function(value) {
  if (is.null(value)) return(NULL)
  if (length(value) == 1L && is.character(value) && !nzchar(value)) return(NULL)
  if (is.list(value) && !is.data.frame(value)) {
    out <- lapply(value, normalize_compare_value)
    keep <- !vapply(out, is.null, logical(1))
    out <- out[keep]
    nms <- names(out)
    if (!is.null(nms)) {
      out <- out[nzchar(nms)]
      out <- out[order(names(out))]
    }
    return(out)
  }
  value
}

header_editor_data <- function(header) {
  columns <- header$columns %||% list()
  spans <- header$spanning_headers %||% list()
  labels <- setNames(vapply(spans, function(x) x$label %||% "", character(1)),
                     vapply(spans, function(x) x$id %||% "", character(1)))
  value <- function(column, field) {
    ref <- as.character(column[[field]] %||% "")
    if (startsWith(field, "spanning_header_") && ref %in% names(labels)) labels[[ref]] else ref
  }
  if (!length(columns)) return(data.frame(
    id=character(), label=character(), condition=character(), display_order=integer(),
    width=numeric(), alignment=character(), spanning_header_1=character(),
    spanning_header_2=character(), stringsAsFactors=FALSE))
  fields <- c("id", "label", "condition", "display_order", "width", "alignment",
              "spanning_header_1", "spanning_header_2")
  out <- lapply(fields, function(field) vapply(columns, value, character(1), field=field))
  names(out) <- fields
  out$display_order <- suppressWarnings(as.integer(out$display_order))
  out$width <- suppressWarnings(as.numeric(out$width))
  as.data.frame(out, stringsAsFactors=FALSE)
}

header_from_editor_data <- function(id, source_data, data) {
  text <- function(x) if (length(x) != 1L || is.na(x)) "" else as.character(x)
  columns <- lapply(seq_len(nrow(data)), function(i) {
    list(id=trimws(text(data$id[[i]])), label=text(data$label[[i]]),
         condition=text(data$condition[[i]]), display_order=suppressWarnings(as.integer(data$display_order[[i]])),
         width=suppressWarnings(as.numeric(data$width[[i]])), alignment=trimws(text(data$alignment[[i]])))
  })
  spans <- list()
  for (level in 1:2) {
    field <- paste0("spanning_header_", level)
    values <- if (field %in% names(data)) trimws(vapply(data[[field]], text, character(1))) else rep("", nrow(data))
    runs <- rle(values); ends <- cumsum(runs$lengths); starts <- ends-runs$lengths+1L; count <- 0L
    for (run in seq_along(runs$values)) {
      label <- runs$values[[run]]; if (!nzchar(label)) next
      count <- count + 1L; span_id <- sprintf("spanning_header_level%d_%d", level, count)
      spans[[length(spans)+1L]] <- list(id=span_id, level=as.integer(level), label=label)
      for (position in seq.int(starts[[run]], ends[[run]])) columns[[position]][[field]] <- span_id
    }
  }
  result <- list(id=id, source_data=as.character(source_data %||% ""), columns=columns)
  if (length(spans)) result$spanning_headers <- spans
  result
}

editor_collection_name <- function(type) paste0(type, "s")
editor_document <- function(workspace, type, id) {
  collection <- workspace[[editor_collection_name(type)]] %||% list()
  hit <- Filter(function(x) identical(as.character(x$id %||% ""), as.character(id %||% "")), collection)
  if (length(hit) == 1L) clone_metadata_value(hit[[1L]]) else NULL
}

metadata_editor_server <- function(input, output, session) {
  workspace <- reactiveVal(new_empty_workspace())
  active_editor <- reactiveVal(NULL)
  active_draft <- reactiveVal(NULL)
  pending_action <- reactiveVal(NULL)
  pending_seed <- reactiveVal(NULL)
  header_table <- reactiveVal(NULL)
  template_value <- reactiveVal(NULL)
  row_table_cache <- reactiveVal(list())
  statistic_table_cache <- reactiveVal(list())
  status <- reactiveVal("Ready.")
  source_text <- reactiveVal("")
  suppress_navigation <- reactiveVal(FALSE)

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
    header_from_editor_data(value$id, input$header_source_data, data)
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
    if (type=="header") { updateTextInput(session,"header_source_data",value=value$source_data %||% ""); header_table(header_editor_data(value)) }
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
    else if (kind=="import") import_now(action$path)
    else if (kind=="generate") generate_now()
  }
  observeEvent(input$guard_cancel, {
    action <- pending_action(); pending_action(NULL); removeModal()
    editor <- active_editor(); if (!is.null(editor)) select_list_row(editor$document_type,editor$document_id)
    if (!is.null(action) && identical(action$kind,"panel")) {
      suppress_navigation(TRUE); updateTabItems(session,"main_nav",selected=switch(editor_type(),population="metadata",header="metadata",table="table_metadata",template="template_editor","metadata"))
      if (editor_type() %in% c("population","header")) updateTabsetPanel(session,"metadata_panel",selected=editor_type())
      session$onFlushed(function() suppress_navigation(FALSE),once=TRUE)
    }
  })
  observeEvent(input$guard_discard, { action <- pending_action(); pending_action(NULL); removeModal(); discard_active(); if (!is.null(action)) execute_action(action) })

  output$population_id_ui <- renderUI(readonly_editor_input("population_id","ID",if (editor_type()=="population") editor_id() else ""))
  output$header_id_ui <- renderUI(readonly_editor_input("header_id","ID",if (editor_type()=="header") editor_id() else ""))
  output$table_id_ui <- renderUI(readonly_editor_input("table_id","ID",if (editor_type()=="table") editor_id() else ""))
  output$template_id_ui <- renderUI(readonly_editor_input("template_id","ID",if (editor_type()=="template") editor_id() else ""))
  for (type in c("population","header","table","template")) local({ t <- type
    output[[paste0(t,"_list")]] <- DT::renderDT({
      ids <- list_ids(t); data.frame(id=ids,stringsAsFactors=FALSE)
    },rownames=FALSE,selection="single",options=list(dom="t",ordering=FALSE),
      callback=JS(sprintf("table.on('click', 'tbody tr', function(){ var d=table.row(this).data(); if(d){ Shiny.setInputValue('%s_list_choice', d[0], {priority:'event'}); }});",t)))
    observeEvent(input[[paste0(t,"_list_choice")]], {
      if (suppress_navigation()) return(); id <- input[[paste0(t,"_list_choice")]]; if (!nzchar(id %||% "")) return()
      if (!identical(editor_id(),id)) request_action(list(kind="switch",type=t,id=id))
    },ignoreInit=TRUE)
  })
  observeEvent(input$main_nav, {
    if (suppress_navigation()) return(); desired <- input$main_nav
    current <- switch(editor_type(),population="metadata",header="metadata",table="table_metadata",template="template_editor","")
    if (!nzchar(desired %||% "") || identical(desired,current)) return()
    panel <- switch(desired,metadata="population",table_metadata="table",template_editor="template",generate_sas="generate","")
    if (identical(panel,"generate")) request_action(list(kind="panel",main=desired,panel="")) else request_action(list(kind="panel",main=desired,panel=panel))
  },ignoreInit=TRUE)
  observeEvent(input$metadata_panel, {
    if (suppress_navigation() || !input$metadata_panel %in% c("population","header") || identical(editor_type(),input$metadata_panel)) return()
    request_action(list(kind="panel",main="metadata",panel=input$metadata_panel))
  },ignoreInit=TRUE)

  save_active <- function(type) {
    if (!identical(editor_type(),type)) return()
    current <- collect_current_editor_value(); draft <- active_draft()
    if (identical(type, "template")) current <- reindex_template(current)
    result <- if (identical(draft$operation,"create")) workspace_create(workspace(),type,current) else workspace_update(workspace(),workspace_target(type,editor_id()),current)
    if (!result$passed) { status(paste("Save failed:",editor_error_text(result$errors))); showNotification(status(),type="error"); return() }
    workspace(result$workspace); id <- current$id; active_draft(NULL); pending_seed(NULL); template_value(NULL); header_table(NULL); activate_editor(type,id); refresh_lists(); status(paste(tools::toTitleCase(type),"saved."))
  }
  for (type in c("population","header","table","template")) local({ t <- type
    observeEvent(input[[paste0(t,"_save")]],save_active(t))
    observeEvent(input[[paste0(t,"_discard")]],{ discard_active(); ids <- list_ids(t); if (length(ids)) activate_editor(t,ids[[1L]]); status("Changes discarded.") })
  })

  show_new_dialog <- function(type) {
    pending_action(list(kind="confirm_new",type=type))
    showModal(modalDialog(title=paste("New",tools::toTitleCase(type)),textInput("new_object_id","ID"),
      footer=tagList(actionButton("confirm_new_object","Create"),actionButton("cancel_new_object","Cancel")),easyClose=FALSE))
  }
  new_seed <- function(type,id) {
    ws <- workspace()
    switch(type,
      population=list(id=id,label="New population",expression="1"),
      header=list(id=id,source_data="adam.adsl",columns=list(list(id="column_001",label="Overall",condition="1",display_order=1L,width=1,alignment="center"))),
      table=list(id=id,population_id=list_ids("population")[[1L]],header_id=list_ids("header")[[1L]],template_id=list_ids("template")[[1L]]),
      template=list(id=id,body=list(stub_header="Characteristic",chunks=list())))
  }
  for (type in c("population","header","table","template")) local({ t <- type
    observeEvent(input[[paste0(t,"_new")]],request_action(list(kind="new",type=t)))
    observeEvent(input[[paste0(t,"_delete")]],{ if (identical(editor_type(),t) && nzchar(editor_id())) request_action(list(kind="delete",type=t,id=editor_id())) })
  })
  observeEvent(input$cancel_new_object,{pending_action(NULL);removeModal()})
  observeEvent(input$confirm_new_object,{
    action <- pending_action(); if (is.null(action) || action$kind!="confirm_new") return()
    id <- trimws(as.character(input$new_object_id %||% "")); type <- action$type
    if (!nzchar(id)) { showNotification("ID is required.",type="error"); return() }
    if (id %in% list_ids(type)) { showNotification("ID already exists.",type="error"); return() }
    if (type=="table" && (!length(list_ids("population")) || !length(list_ids("header")) || !length(list_ids("template")))) { showNotification("Create a population, header, and template first.",type="error"); return() }
    removeModal(); pending_action(NULL); seed <- new_seed(type,id); activate_editor(type,id,"create",seed); status(paste("New",type,"pending."))
  })

  begin_delete <- function(type,id) {
    draft <- active_draft()
    if (!is.null(draft) && draft$operation=="create" && editor_id()==id) { clear_editor(); ids<-list_ids(type); if(length(ids)) activate_editor(type,ids[[1L]]); status("New object discarded."); return() }
    impact <- workspace_delete_impact(workspace(),type,id)
    if (!impact$allowed) { showNotification(editor_error_text(impact$errors),type="error"); return() }
    pending_action(list(kind="confirm_delete",target=impact$target,type=type,id=id))
    showModal(modalDialog(title="Confirm delete",paste("Delete",type,id,"?"),footer=tagList(actionButton("cancel_delete","Cancel"),actionButton("confirm_delete","Delete",class="btn-danger")),easyClose=FALSE))
  }
  observeEvent(input$cancel_delete,{pending_action(NULL);removeModal()})
  observeEvent(input$confirm_delete,{
    action<-pending_action(); if(is.null(action)||action$kind!="confirm_delete") return(); removeModal(); pending_action(NULL)
    result<-workspace_delete_immediate(workspace(),action$target); if(!result$passed){showNotification(editor_error_text(result$errors),type="error");return()}
    workspace(result$workspace); clear_editor(); ids<-list_ids(action$type); if(length(ids)) activate_editor(action$type,ids[[1L]]); refresh_lists(); status("Object deleted.")
  })

  output$header_columns_table <- DT::renderDT(header_table() %||% data.frame(),editable=list(target="cell",disable=list(columns=0)),rownames=FALSE,selection="single",options=list(ordering=FALSE))
  observeEvent(input$header_columns_table_cell_edit,{
    info<-input$header_columns_table_cell_edit; data<-header_table(); if(is.null(data)) return()
    row<-as.integer(info$row); column<-as.integer(info$col)+1L; if(row<1L||row>nrow(data)||column<1L||column>ncol(data)||column==1L)return()
    field<-names(data)[[column]]; value<-info$value
    if(field=="display_order")value<-suppressWarnings(as.integer(value)) else if(field=="width")value<-suppressWarnings(as.numeric(value)) else value<-as.character(value)
    data[row,field]<-value; header_table(data)
  })
  observeEvent(input$header_column_new,{
    data<-header_table(); if(is.null(data))return(); n<-nrow(data)+1L
    data<-rbind(data,data.frame(id=sprintf("column_%03d",n),label="New column",condition="1",display_order=n,width=1,alignment="center",spanning_header_1="",spanning_header_2="",stringsAsFactors=FALSE)); header_table(data)
  })
  observeEvent(input$header_column_delete,{data<-header_table(); row<-input$header_columns_table_rows_selected; if(is.null(data)||!length(row))return(); header_table(data[-row[[1L]],,drop=FALSE])})

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
  observeEvent(input$chunk_add, {
    showModal(modalDialog(
      title = "Add chunk",
      selectInput(
        "new_chunk_type", "Chunk type",
        choices = c(
          "Continuous summary" = "continuous_summary",
          "Categorical summary (non-exclusive)" = "categorical_summary_nonexclusive",
          "Categorical summary (exclusive)" = "categorical_summary_exclusive",
          "Hierarchical summary" = "hierarchical_summary"
        )
      ),
      footer = tagList(
        actionButton("cancel_new_chunk", "Cancel"),
        actionButton("confirm_new_chunk", "Add", class = "btn-primary")
      ),
      easyClose = FALSE
    ))
  })
  observeEvent(input$cancel_new_chunk, removeModal())
  observeEvent(input$confirm_new_chunk, {
    type <- as.character(input$new_chunk_type %||% "")
    if (!type %in% c("continuous_summary", "categorical_summary_nonexclusive",
                     "categorical_summary_exclusive", "hierarchical_summary")) return()
    removeModal()
    mutate_template(function(x) {
      n <- length(x$body$chunks %||% list()) + 1L
      x$body$chunks[[n]] <- new_chunk_seed(type)
      x
    })
  })
  output$chunk_cards <- renderUI({ value<-template_value(); if(is.null(value)||editor_type()!="template")return(NULL); chunks<-value$body$chunks %||% list(); tagList(lapply(seq_along(chunks),function(i) chunk_card_ui(chunks[[i]],i))) })

  observe({
    value <- template_value(); if (is.null(value)) return()
    for (i in seq_along(value$body$chunks %||% list())) {
      chunk <- value$body$chunks[[i]]; p <- paste0("chunk_", i, "_")
      if (identical(chunk$type, "hierarchical_summary")) {
        output[[paste0(p,"levels")]] <- DT::renderDT({
          data.frame(id=vapply(chunk$levels %||% list(),function(x)x$id,character(1)),stringsAsFactors=FALSE)
        },rownames=FALSE,selection="single",options=list(dom="t",ordering=FALSE))
        output[[paste0(p,"analysis_blocks")]] <- DT::renderDT({
          data.frame(id=vapply(chunk$analysis_blocks %||% list(),function(x)x$id,character(1)),stringsAsFactors=FALSE)
        },rownames=FALSE,selection="single",options=list(dom="t",ordering=FALSE))
      } else {
        local({ chunk_i <- chunk; prefix_i <- p
          output[[paste0(prefix_i,"rows")]] <- DT::renderDT({
            rows_table_data(chunk_i$rows)
          },editable=list(target="cell",disable=list(columns=c(0,7))),rownames=FALSE,selection="single",
          colnames=c("Type","Label","Indent","Condition","Statistics","Digits","Cell format",".row_id"),
          options=list(dom="t",ordering=FALSE,columnDefs=list(list(visible=FALSE,targets=7))))
        })
      }
      if (identical(chunk$type, "hierarchical_summary")) for (b in seq_along(chunk$analysis_blocks %||% list())) {
        local({ block_i <- chunk$analysis_blocks[[b]]; bp <- paste0(p, "block_", b, "_")
          output[[paste0(bp, "rows")]] <- DT::renderDT({ rows_table_data(block_i$rows) }, editable=list(target="cell",disable=list(columns=c(0,7))), rownames=FALSE, selection="single",
            colnames=c("Type","Label","Indent","Condition","Statistics","Digits","Cell format",".row_id"), options=list(dom="t",ordering=FALSE,columnDefs=list(list(visible=FALSE,targets=7))))
        })
      }
    }
  })

  observer_registry <- new.env(parent = emptyenv())
  register_once <- function(key, factory) {
    if (exists(key, observer_registry, inherits = FALSE)) return(invisible(NULL))
    assign(key, factory(), observer_registry)
    invisible(NULL)
  }
  register_template_actions <- observe({
    value<-template_value(); if(is.null(value))return(); chunks<-value$body$chunks %||% list()
    lapply(seq_along(chunks),function(i){ local({index<-i
        register_dt_edit <- function(prefix, rows_getter) {
        register_once(paste0("dt-", prefix, "-rows-edit"), function() observeEvent(input[[paste0(prefix, "rows_cell_edit")]], {
          info <- input[[paste0(prefix, "rows_cell_edit")]]; cache <- row_table_cache()
          key <- paste0(prefix, "rows"); data <- cache[[key]] %||% rows_table_data(rows_getter())
          row <- as.integer(info$row); col <- as.integer(info$col) + 1L
          if (row >= 1L && row <= nrow(data) && col >= 2L && col <= 7L) {
            data[row, col] <- if (col == 3L) suppressWarnings(as.integer(info$value)) else as.character(info$value)
            cache[[key]] <- data; row_table_cache(cache)
          }
        }, ignoreInit=TRUE))
      }
      register_dt_edit(paste0("chunk_", index, "_"), function() (template_value()$body$chunks[[index]]$rows %||% list()))
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b; register_dt_edit(paste0("chunk_", index, "_block_", block_index, "_"), function() (template_value()$body$chunks[[index]]$analysis_blocks[[block_index]]$rows %||% list())) })
      register_statistic_actions <- function(prefix, block_index = NULL) {
        for (action in c("new", "delete", "up", "down")) local({ a <- action
          register_once(paste0("stat-", prefix, "-", a), function() observeEvent(input[[paste0(prefix, "statistic_", a)]], {
            mutate_template(function(x) {
              rows <- if (is.null(block_index)) x$body$chunks[[index]]$rows %||% list() else x$body$chunks[[index]]$analysis_blocks[[block_index]]$rows %||% list()
              row_selected <- input[[paste0(prefix, "rows_rows_selected")]]
              stat_selected <- input[[paste0(prefix, "statistics_rows_selected")]]
              if (a == "new") {
                row_pos <- if (length(row_selected)) row_selected[[1L]] else if (length(rows)) 1L else NA_integer_
                if (!is.na(row_pos)) {
                  analysis_type <- if (is.null(block_index)) x$body$chunks[[index]]$type else x$body$chunks[[index]]$analysis_blocks[[block_index]]$type
                  allowed <- if (identical(analysis_type,"continuous_summary")) c("n","mean","sd","median","q1","q3","min","max") else c("n","pct")
                  existing <- vapply(rows[[row_pos]]$statistics %||% list(),function(s)s$id,character(1)); next_id <- setdiff(allowed,existing)
                  if (length(next_id)) rows[[row_pos]]$statistics[[length(existing)+1L]] <- list(id=next_id[[1L]])
                }
              } else {
                map <- do.call(rbind, lapply(seq_along(rows), function(r) if(length(rows[[r]]$statistics %||% list())) cbind(row=r,stat=seq_along(rows[[r]]$statistics))))
                flat <- if (length(stat_selected)) stat_selected[[1L]] else if (!is.null(map)) nrow(map) else NA_integer_
                if (!is.null(map) && flat >= 1L && flat <= nrow(map)) {
                  row_pos <- map[flat,"row"]; stat_pos <- map[flat,"stat"]; stats <- rows[[row_pos]]$statistics
                  if (a == "delete") stats <- stats[-stat_pos] else stats <- move_item(stats, stat_pos, a)
                  rows[[row_pos]]$statistics <- stats
                }
              }
              if (is.null(block_index)) x$body$chunks[[index]]$rows <- rows else x$body$chunks[[index]]$analysis_blocks[[block_index]]$rows <- rows
              x
            })
          }, ignoreInit=TRUE))
        })
      }
      register_statistic_actions(paste0("chunk_", index, "_"))
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b; register_statistic_actions(paste0("chunk_", index, "_block_", block_index, "_"), block_index) })
      register_once(paste0("chunk-",index,"-delete"),function() observeEvent(input[[paste0("chunk_",index,"_delete")]],mutate_template(function(x){x$body$chunks<-x$body$chunks[-index];x}),ignoreInit=TRUE))
      register_once(paste0("chunk-",index,"-up"),function() observeEvent(input[[paste0("chunk_",index,"_up")]],mutate_template(function(x){x$body$chunks<-move_item(x$body$chunks,index,"up");x}),ignoreInit=TRUE))
      register_once(paste0("chunk-",index,"-down"),function() observeEvent(input[[paste0("chunk_",index,"_down")]],mutate_template(function(x){x$body$chunks<-move_item(x$body$chunks,index,"down");x}),ignoreInit=TRUE))
      for(kind in c("row","level","block")) for(action in c("new","delete","up","down")) local({k<-kind;a<-action
        register_once(paste0("chunk-",index,"-",k,"-",a),function() observeEvent(input[[paste0("chunk_",index,"_",k,"_",a)]],{
          mutate_template(function(x){ch<-x$body$chunks[[index]]; field<-switch(k,row="rows",level="levels",block="analysis_blocks");items<-ch[[field]] %||% list(); selected<-input[[paste0("chunk_",index,"_",field,"_rows_selected")]]; pos<-if(length(selected))selected[[1L]] else length(items)
            if(a=="new") { n<-length(items)+1L; items[[n]]<-switch(k,row=list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}"),level=list(id="level",variable="VAR",order_variable="VAR",order_direction="asc",node_role="label",missing_policy="exclude"),block=list(id="analysis",anchor_level=(ch$levels[[1L]]$id %||% "level"),placement="below",type="continuous_summary",counting_unit="record",analysis_variable="AVAL",rows=list(list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}")))) }
            if(a=="delete"&&length(selected))items<-items[-pos]; if(a%in%c("up","down")&&length(selected))items<-move_item(items,pos,a); ch[[field]]<-items;x$body$chunks[[index]]<-ch;x })
        },ignoreInit=TRUE))
      })
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b
        for (action in c("new", "delete", "up", "down")) local({ a <- action
          register_once(paste0("chunk-", index, "-block-", block_index, "-row-", a), function() observeEvent(input[[paste0("chunk_", index, "_block_", block_index, "_row_", a)]], {
            mutate_template(function(x) {
              block <- x$body$chunks[[index]]$analysis_blocks[[block_index]]; items <- block$rows %||% list()
              selected <- input[[paste0("chunk_", index, "_block_", block_index, "_rows_rows_selected")]]; pos <- if(length(selected)) selected[[1L]] else length(items)
              if (a == "new") items[[length(items)+1L]] <- list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}")
              if (a == "delete" && length(selected)) items <- items[-pos]
              if (a %in% c("up","down") && length(selected)) items <- move_item(items,pos,a)
              block$rows <- items; x$body$chunks[[index]]$analysis_blocks[[block_index]] <- block; x
            })
          }, ignoreInit=TRUE))
        })
      })
    })})
  })

  import_now <- function(path) {
    bytes<-tryCatch(readBin(path,"raw",n=file.info(path)$size),error=function(e)NULL); if(is.null(bytes)){showNotification("Import failed.",type="error");return()}
    result<-application_import_bundle(workspace(),bytes); if(!result$passed){status(paste("Import failed:",editor_error_text(result$errors)));showNotification(status(),type="error");return()}
    workspace(result$workspace); clear_editor(); refresh_lists(); ids<-list_ids("population"); if(length(ids))activate_editor("population",ids[[1L]]); status("Metadata imported.")
  }
  observeEvent(input$bundle,{req(input$bundle$datapath); path<-input$bundle$datapath
    if(is_guarded())show_guard(list(kind="import",path=path)) else if(sum(vapply(c("population","header","table","template"),function(t)length(list_ids(t)),integer(1)))>0L){pending_action(list(kind="confirm_import",path=path));showModal(modalDialog(title="Replace workspace?","Importing this bundle will replace the current workspace.",footer=tagList(actionButton("cancel_import","Cancel"),actionButton("confirm_import","Import")),easyClose=FALSE))}else import_now(path)
  })
  observeEvent(input$cancel_import,{pending_action(NULL);removeModal()})
  observeEvent(input$confirm_import,{action<-pending_action();pending_action(NULL);removeModal();if(!is.null(action))import_now(action$path)})
  generate_now <- function(){result<-application_generate_source(workspace(),input$generate_table);if(!result$passed){status(paste("Generation failed:",editor_error_text(result$errors)));showNotification(status(),type="error");return()};source_text(result$value);status("SAS source generated.")}
  observeEvent(input$generate,request_action(list(kind="generate")))
  output$status<-renderText(status()); output$source<-renderText(source_text())
  output$download_bundle<-downloadHandler(filename=function()"metadata_bundle.zip",content=function(file){result<-application_export_bundle(workspace());if(result$passed)writeBin(result$value$bytes,file)})
  output$download_sas<-downloadHandler(filename=function()paste0(input$generate_table %||% "table",".sas"),content=function(file)writeLines(source_text(),file,useBytes=TRUE))
}

chunk_row_ui <- function(row,prefix,index) {
  p<-paste0(prefix,"row_",index,"_"); tags$div(class="well",
    readonly_editor_input(paste0(p,"id"),"Row ID",row$id),readonly_editor_input(paste0(p,"type"),"Row type",row$type),
    textInput(paste0(p,"label"),"Label",row$label %||% ""),numericInput(paste0(p,"indent"),"Indent",row$indent_level %||% 0,min=0),
    if(identical(row$type,"analysis")) tagList(if(!is.null(row$condition))textInput(paste0(p,"condition"),"Condition",row$condition),textInput(paste0(p,"cell_format"),"Cell format",row$cell_format %||% ""),
      tagList(lapply(seq_along(row$statistics %||% list()),function(s){stat<-row$statistics[[s]];sp<-paste0(p,"stat_",s,"_");tags$div(readonly_editor_input(paste0(sp,"id"),"Statistic",stat$id),textInput(paste0(sp,"digits"),"Digits",as.character(stat$digits %||% "")))}))))
}

  chunk_card_ui <- function(chunk,index) {
  p<-paste0("chunk_",index,"_"); uid <- chunk$ui_uid %||% sprintf("chunk_%06d", index)
  common<-tagList(readonly_editor_input(paste0(p,"id"),"ID",chunk$id),readonly_editor_input(paste0(p,"type"),"Type",chunk$type),tags$small(class="text-muted",paste("UI identity:",uid)),textInput(paste0(p,"source_data"),"Source data",chunk$source_data %||% ""),textInput(paste0(p,"filter"),"Filter",chunk$filter %||% ""),actionButton(paste0(p,"delete"),"Delete chunk"),actionButton(paste0(p,"up"),"Move up"),actionButton(paste0(p,"down"),"Move down"))
  if(chunk$type=="continuous_summary")specific<-tagList(textInput(paste0(p,"analysis_variable"),"Analysis variable",chunk$analysis_variable %||% ""),collection_buttons(p,"row","rows"))
  else if(chunk$type%in%c("categorical_summary_nonexclusive","categorical_summary_exclusive"))specific<-tagList(selectInput(paste0(p,"den_type"),"Denominator type",c("header_population","non_missing","custom"),selected=chunk$denominator$type),textInput(paste0(p,"den_variable"),"Denominator variable",chunk$denominator$variable %||% ""),textInput(paste0(p,"den_expression"),"Denominator expression",chunk$denominator$expression %||% ""),collection_buttons(p,"row","rows"))
  else { sc<-chunk$source_contract %||% list(); specific<-tagList(h4("Source contract"),selectInput(paste0(p,"grain"),"Grain",c("subject","record","observation"),selected=sc$grain),textInput(paste0(p,"subject_key"),"Subject key",sc$subject_key %||% ""),textInput(paste0(p,"record_key"),"Record key",paste(sc$record_key %||% character(),collapse=", ")),selectInput(paste0(p,"duplicate_policy"),"Duplicate policy",c("error","first","last"),selected=sc$duplicate_policy),h4("Levels"),collection_buttons(p,"level","levels"),tagList(lapply(seq_along(chunk$levels %||% list()),function(j)level_ui(chunk$levels[[j]],p,j,chunk))),h4("Analysis blocks"),collection_buttons(p,"block","analysis_blocks"),tagList(lapply(seq_along(chunk$analysis_blocks %||% list()),function(b)block_ui(chunk$analysis_blocks[[b]],p,b,chunk)))) }
  box(id=paste0("chunk-card-", uid), title=paste("Chunk",index,chunk$id),width=12,status="info",solidHeader=TRUE,common,specific)
}

collection_buttons <- function(prefix,kind,table_name) tagList(actionButton(paste0(prefix,kind,"_new"),paste("Add",kind)),actionButton(paste0(prefix,kind,"_delete"),paste("Delete",kind)),actionButton(paste0(prefix,kind,"_up"),"Move up"),actionButton(paste0(prefix,kind,"_down"),"Move down"),DTOutput(paste0(prefix,table_name)))

  statistics_controls <- function(prefix) NULL

level_ui <- function(level,prefix,index,chunk) { p<-paste0(prefix,"level_",index,"_"); ids<-vapply(chunk$levels %||% list(),function(x)x$id,character(1)); tags$div(class="well",tags$small(class="text-muted",paste("UI identity:",level$ui_uid %||% "")),readonly_editor_input(paste0(p,"id"),"Level ID",level$id),selectInput(paste0(p,"parent_level"),"Parent level",c("",ids),selected=level$parent_level %||% ""),textInput(paste0(p,"variable"),"Variable",level$variable),textInput(paste0(p,"label_variable"),"Label variable",level$label_variable %||% ""),textInput(paste0(p,"order_variable"),"Order variable",level$order_variable),selectInput(paste0(p,"order_direction"),"Order direction",c("asc","desc"),selected=level$order_direction),selectInput(paste0(p,"node_role"),"Node role",c("label","analysis"),selected=level$node_role),textInput(paste0(p,"node_analysis_id"),"Node analysis ID",level$node_analysis_id %||% ""),selectInput(paste0(p,"missing_policy"),"Missing policy",c("exclude","label","error"),selected=level$missing_policy),textInput(paste0(p,"missing_label"),"Missing label",level$missing_label %||% "")) }

  block_ui <- function(block,prefix,index,chunk) { p<-paste0(prefix,"block_",index,"_"); types<-c("continuous_summary","categorical_summary_nonexclusive","categorical_summary_exclusive"); levels<-vapply(chunk$levels %||% list(),function(x)x$id,character(1)); tags$div(class="well",tags$small(class="text-muted",paste("UI identity:",block$ui_uid %||% "")),readonly_editor_input(paste0(p,"id"),"Block ID",block$id),selectInput(paste0(p,"anchor_level"),"Anchor level",levels,selected=block$anchor_level),selectInput(paste0(p,"placement"),"Placement",c("same_row","below"),selected=block$placement),selectInput(paste0(p,"type"),"Type",types,selected=block$type),selectInput(paste0(p,"counting_unit"),"Counting unit",c("record","distinct_subject","distinct_key"),selected=block$counting_unit),textInput(paste0(p,"distinct_key"),"Distinct key",paste(block$distinct_key %||% character(),collapse=", ")),if(block$type=="continuous_summary")textInput(paste0(p,"analysis_variable"),"Analysis variable",block$analysis_variable %||% "") else tagList(selectInput(paste0(p,"den_scope"),"Denominator scope",c("header_population","current_group","non_missing","custom"),selected=block$denominator$scope),selectInput(paste0(p,"den_unit"),"Denominator unit",c("record","distinct_subject","distinct_key"),selected=block$denominator$unit),textInput(paste0(p,"den_variable"),"Denominator variable",block$denominator$variable %||% ""),textInput(paste0(p,"den_expression"),"Denominator expression",block$denominator$expression %||% "")),collection_buttons(p,"row","rows")) }
