library(shiny)
library(shinydashboard)
library(DT)

project_root <- normalizePath(getwd(), mustWork = FALSE)
source_order <- c(
  "src/core/errors.R", "src/chunks/registry.R", "src/metadata/model.R",
  "src/metadata/yaml_codec.R", "src/metadata/workspace.R",
  "src/generator/source_generator.R", "src/emitters/continuous.R",
  "src/emitters/categorical.R", "src/emitters/hierarchical.R",
  "src/emitters/precision.R", "src/emitters/result_render.R",
  "src/application/orchestration.R"
)
invisible(lapply(file.path(project_root, source_order), source, local = FALSE))

error_text <- function(errors) {
  if (length(errors) == 0L) return("Operation failed.")
  paste(vapply(errors, function(item) item$message %||% "Operation failed.", character(1L)),
        collapse = " ")
}

# Shiny's textInput does not expose a readonly argument.  Use a native input
# element so generated IDs/types remain visible while non-editable.
readonly_text_input <- function(input_id, label, value = "") {
  tags$div(class = "form-group shiny-input-container",
           tags$label(class = "control-label", `for` = input_id, label),
           tags$input(id = input_id, type = "text", class = "form-control",
                      value = value %||% "", readonly = "readonly"))
}

ui <- dashboardPage(
  dashboardHeader(title = "SAS Code Generator",
    dropdownMenu(type = "notifications", badgeStatus = NULL,
      notificationItem(text = "Workspace notifications", icon = icon("info")))),
  dashboardSidebar(
    sidebarMenu(id = "main_nav",
      menuItem("Metadata", tabName = "metadata", icon = icon("database")),
      menuItem("Table Metadata", tabName = "table_metadata", icon = icon("table")),
      menuItem("Template Editor", tabName = "template_editor", icon = icon("file")),
      menuItem("Generate SAS", tabName = "generate_sas", icon = icon("code"))),
    tags$hr(), fileInput("bundle", "Metadata bundle (ZIP)", accept = ".zip"),
    downloadButton("download_bundle", "Download metadata"), actionButton("discard", "Discard active edit")),
  dashboardBody(tabItems(
    tabItem(tabName = "metadata", tabsetPanel(
      tabPanel("Population", fluidRow(
          box(title = "Populations", width = 4, actionButton("population_new", "New population"), actionButton("population_delete", "Delete population"), DTOutput("population_list")),
        box(title = "Population metadata", width = 8, status = "primary", solidHeader = TRUE,
          tags$div(style = "display:none", selectInput("population", "Selected population", choices = character())),
          textInput("population_label", "Label"), textAreaInput("population_expression", "SAS expression", rows = 3),
            actionButton("save", "Save"), actionButton("cancel", "Discard changes")))),
      tabPanel("Header", fluidRow(
          box(title = "Headers", width = 4, actionButton("header_new", "New header"), actionButton("header_delete", "Delete header"), DTOutput("header_list")),
        box(title = "Header metadata", width = 8, status = "primary", solidHeader = TRUE,
          tags$div(style = "display:none", selectInput("header", "Selected header", choices = character())),
          textInput("header_source_data", "Source data"), h4("Spanning headers"), DTOutput("header_spanning_table"),
          h4("Header columns"), actionButton("header_column_new", "Add column"), actionButton("header_column_delete", "Delete column"), DTOutput("header_columns_table"), actionButton("header_save", "Save"), actionButton("header_discard", "Discard changes"))))
    )),
    tabItem(tabName = "table_metadata", fluidRow(
      box(title = "Tables", width = 4, actionButton("table_new", "New table"), actionButton("table_delete", "Delete table"), DTOutput("table_list")),
      box(title = "Table metadata", width = 8, status = "primary", solidHeader = TRUE,
        tags$div(style = "display:none", selectInput("table", "Selected table", choices = character())),
        textInput("table_population_id", "Population ID"), textInput("table_header_id", "Header ID"),
        textInput("table_template_id", "Template ID"), textAreaInput("table_custom_before", "Custom code before", rows = 4),
        textAreaInput("table_custom_after", "Custom code after", rows = 4), actionButton("table_save", "Save"), actionButton("table_cancel", "Discard changes"))
    )),
    tabItem(tabName = "template_editor", fluidRow(
      box(title = "Templates", width = 4, actionButton("template_new", "New template"), actionButton("template_delete", "Delete template"), DTOutput("template_list")),
      box(title = "Template metadata", width = 8, status = "primary", solidHeader = TRUE,
        tags$div(style = "display:none", selectInput("template", "Selected template", choices = character())),
        textInput("template_stub_header", "Stub header"), uiOutput("chunk_cards"),
        tags$div(style="display:none", selectInput("chunk", "Selected chunk", choices = character())),
        tags$div(style="display:none", textInput("chunk_source_data", "Source data")),
        tags$div(style="display:none", textInput("chunk_filter", "Filter")),
        tags$div(style="display:none", textInput("chunk_row_label", "First row label")),
        tags$div(style="display:none", textInput("chunk_statistic_id", "First statistic ID")),
        tags$div(style="display:none", numericInput("chunk_statistic_digits", "Statistic digits", value = NA, min = 0)),
        actionButton("chunk_add", "Add chunk"), actionButton("chunk_delete", "Delete chunk"),
        actionButton("chunk_up", "Move up"), actionButton("chunk_down", "Move down"), DTOutput("chunk_rows_table"))
    )),
    tabItem(tabName = "generate_sas", box(title = "Generate SAS", width = 12, status = "success", solidHeader = TRUE,
      selectInput("generate_table", "Table", choices = character()), actionButton("generate", "Generate SAS", icon = icon("play")),
      downloadButton("download_sas", "Download SAS"), verbatimTextOutput("status"), verbatimTextOutput("source")))
  )))

server <- function(input, output, session) {
  session_state <- reactiveValues(
    workspace_status = "empty", workspace = new_empty_workspace(), import_error = NULL,
    navigation = list(active_panel = "metadata", selected_population_id = NULL,
                      selected_header_id = NULL, selected_table_id = NULL,
                      selected_template_id = NULL), active_draft = NULL,
    delete_impact = NULL,
    generation = list(table_id = NULL, status = "idle", source_text = "", errors = list())
    , suppress_selection = FALSE, template_observer_key = NULL
  )
  # Compatibility accessor: SessionState remains the only reactive workspace owner.
  workspace <- function(value) {
    if (missing(value)) return(session_state$workspace)
    session_state$workspace <- value
    invisible(value)
  }
  status <- reactiveVal("Ready.")
  source_text <- function(value) {
    if (missing(value)) return(session_state$generation$source_text %||% "")
    generation <- session_state$generation
    generation$source_text <- value
    session_state$generation <- generation
    invisible(value)
  }
  draft_target <- reactiveVal(NULL)
  draft_identity <- reactiveVal(NULL)
  selected_target <- reactiveVal(NULL)
  pending_bundle <- reactiveVal(NULL)
  pending_switch <- reactiveVal(NULL)
  request_switch <- function(type, id, input_id) {
    pending_switch(list(type=type, id=id, input_id=input_id))
    showModal(modalDialog(title="Unsaved changes", "Save or discard the active draft before switching?",
      footer=tagList(actionButton("switch_discard", "Discard changes"), actionButton("switch_cancel", "Cancel"))))
  }

  observeEvent(input$main_nav, {
    session_state$navigation$active_panel <- input$main_nav
  }, ignoreInit = TRUE)

  refresh_tables <- function(value) {
    session_state$suppress_selection <- TRUE
    session_state$workspace <- value
    displayed <- if (!is.null(value$active_draft)) workspace_overlay_active_draft(value) else value
    session_state$workspace_status <- if (length(displayed$tables) > 0L) "loaded" else "empty"
    ids <- vapply(displayed$tables, `[[`, "", "id")
    updateSelectInput(session, "table", choices = ids,
                      selected = if (length(ids) > 0L) ids[[1L]] else character())
    updateSelectInput(session, "generate_table", choices = ids,
                      selected = if (length(ids) > 0L) ids[[1L]] else character())
    population_ids <- vapply(displayed$populations, `[[`, "", "id")
    updateSelectInput(session, "population", choices = population_ids,
                      selected = if (length(population_ids) > 0L) population_ids[[1L]] else character())
    header_ids <- vapply(displayed$headers, `[[`, "", "id")
    updateSelectInput(session, "header", choices = header_ids,
                      selected = if (length(header_ids) > 0L) header_ids[[1L]] else character())
    updateSelectInput(session, "header2", choices = header_ids,
                      selected = if (length(header_ids) > 0L) header_ids[[1L]] else character())
    template_ids <- vapply(displayed$templates, `[[`, "", "id")
    updateSelectInput(session, "template", choices = template_ids,
                      selected = if (length(template_ids) > 0L) template_ids[[1L]] else character())
    chunks <- unlist(lapply(displayed$templates, function(template) template$body$chunks %||% list()), recursive = FALSE)
    chunk_ids <- if (length(chunks) > 0L) vapply(chunks, `[[`, "", "id") else character()
    updateSelectInput(session, "chunk", choices = chunk_ids,
                      selected = if (length(chunk_ids) > 0L) chunk_ids[[1L]] else character())
    session$onFlushed(function() session_state$suppress_selection <- FALSE, once = TRUE)
  }

  output$population_list <- DT::renderDT({
    data.frame(id = vapply(workspace()$populations, `[[`, "", "id"),
               label = vapply(workspace()$populations, `[[`, "", "label"), stringsAsFactors = FALSE)
  }, rownames = FALSE, selection = "single", options = list(dom = "t"))
  output$header_list <- DT::renderDT({
    data.frame(id = vapply(workspace()$headers, `[[`, "", "id"), stringsAsFactors = FALSE)
  }, rownames = FALSE, selection = "single", options = list(dom = "t"))
  output$table_list <- DT::renderDT({
    data.frame(id = vapply(workspace()$tables, `[[`, "", "id"), stringsAsFactors = FALSE)
  }, rownames = FALSE, selection = "single", options = list(dom = "t"))
  output$template_list <- DT::renderDT({
    data.frame(id = vapply(workspace()$templates, `[[`, "", "id"), stringsAsFactors = FALSE)
  }, rownames = FALSE, selection = "single", options = list(dom = "t"))
  observeEvent(input$population_list_rows_selected, { i <- input$population_list_rows_selected; if (length(i)) updateSelectInput(session, "population", selected = vapply(workspace()$populations, `[[`, "", "id")[[i]]) })
  observeEvent(input$header_list_rows_selected, { i <- input$header_list_rows_selected; if (length(i)) updateSelectInput(session, "header", selected = vapply(workspace()$headers, `[[`, "", "id")[[i]]) })
  observeEvent(input$table_list_rows_selected, { i <- input$table_list_rows_selected; if (length(i)) updateSelectInput(session, "table", selected = vapply(workspace()$tables, `[[`, "", "id")[[i]]) })
  observeEvent(input$template_list_rows_selected, { i <- input$template_list_rows_selected; if (length(i)) updateSelectInput(session, "template", selected = vapply(workspace()$templates, `[[`, "", "id")[[i]]) })
  output$chunk_cards <- renderUI({
    shown <- if (!is.null(workspace()$active_draft)) workspace_overlay_active_draft(workspace()) else workspace()
    item <- Filter(function(value) identical(value$id, input$template), shown$templates)
    if (length(item) != 1L) return(NULL)
    body <- item[[1L]]$body %||% list()
    chunks <- body$chunks %||% list()
    if (!is.list(chunks) || !length(chunks)) return(NULL)
    tagList(lapply(seq_along(chunks), function(i) {
      chunk <- chunks[[i]]
      if (!is.list(chunk)) return(NULL)
      prefix <- paste0("chunk_card_", i, "_")
      common <- list(
        readonly_text_input(paste0(prefix, "id"), "ID", value = chunk$id %||% ""),
        readonly_text_input(paste0(prefix, "type"), "Type", value = chunk$type %||% ""),
        textInput(paste0(prefix, "source_data"), "Source data", value = chunk$source_data %||% ""),
        textInput(paste0(prefix, "filter"), "Filter", value = chunk$filter %||% "")
      )
      specific <- list()
      if (identical(chunk$type, "continuous_summary")) {
        specific <- list(textInput(paste0(prefix, "analysis_variable"), "Analysis variable", value = chunk$analysis_variable %||% ""))
      } else if (chunk$type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
        den <- chunk$denominator %||% list()
        specific <- list(
          h4("Denominator"),
          textInput(paste0(prefix, "den_scope"), "Scope", value = den$scope %||% ""),
          textInput(paste0(prefix, "den_unit"), "Unit", value = den$unit %||% ""),
          textInput(paste0(prefix, "den_variable"), "Variable", value = den$variable %||% ""),
          textInput(paste0(prefix, "den_expression"), "Expression", value = den$expression %||% "")
        )
      } else if (identical(chunk$type, "hierarchical_summary")) {
        sc <- chunk$source_contract %||% list()
        specific <- list(
          h4("Source contract"),
          textInput(paste0(prefix, "sc_grain"), "Grain", value = sc$grain %||% ""),
          textInput(paste0(prefix, "sc_subject_key"), "Subject key", value = sc$subject_key %||% ""),
          textInput(paste0(prefix, "sc_record_key"), "Record key", value = paste(sc$record_key %||% character(), collapse = ", ")),
          textInput(paste0(prefix, "sc_duplicate_policy"), "Duplicate policy", value = sc$duplicate_policy %||% ""),
          h4("Levels"), actionButton(paste0(prefix, "level_new"), "Add level"),
          actionButton(paste0(prefix, "level_delete"), "Delete level"),
          actionButton(paste0(prefix, "level_up"), "Move level up"),
          actionButton(paste0(prefix, "level_down"), "Move level down"),
          DTOutput(paste0(prefix, "levels")),
          uiOutput(paste0(prefix, "level_parent_ui")),
          h4("Analysis blocks"), selectInput(paste0(prefix, "block_type"), "Selected block type", choices = c("continuous_summary", "categorical_summary_nonexclusive", "categorical_summary_exclusive"), selected = if (length(chunk$analysis_blocks %||% list())) chunk$analysis_blocks[[1L]]$type else "continuous_summary"),
          actionButton(paste0(prefix, "block_new"), "Add analysis block"),
          actionButton(paste0(prefix, "block_delete"), "Delete analysis block"),
          actionButton(paste0(prefix, "block_up"), "Move block up"),
          actionButton(paste0(prefix, "block_down"), "Move block down"),
          DTOutput(paste0(prefix, "blocks")),
          uiOutput(paste0(prefix, "block_rows_ui"))
        )
      }
      rows <- if (identical(chunk$type, "hierarchical_summary")) NULL else {
        row_ui <- lapply(seq_along(chunk$rows %||% list()), function(r) {
          tagList(h5(paste("Statistics for row", r)),
                  actionButton(paste0(prefix, "stats_new_", r), "Add statistic"),
                  actionButton(paste0(prefix, "stats_delete_", r), "Delete statistic"),
                  actionButton(paste0(prefix, "stats_up_", r), "Move statistic up"),
                  actionButton(paste0(prefix, "stats_down_", r), "Move statistic down"),
                  DTOutput(paste0(prefix, "stats_", r)))
        })
        tagList(actionButton(paste0(prefix, "row_new"), "Add row"),
                actionButton(paste0(prefix, "row_delete"), "Delete row"),
                actionButton(paste0(prefix, "row_up"), "Move row up"),
                actionButton(paste0(prefix, "row_down"), "Move row down"),
                DTOutput(paste0(prefix, "rows")), row_ui)
      }
      box(title = paste("Chunk", i, chunk$id %||% ""), width = 12, status = "info", solidHeader = TRUE,
          tagList(common, specific, if (!is.null(rows)) list(h4("Rows"), rows) else NULL))
    }))
  })

  # Render card-level nested tables from the currently displayed (draft-aware) template.
  observe({
    shown <- if (!is.null(workspace()$active_draft)) workspace_overlay_active_draft(workspace()) else workspace()
    item <- Filter(function(value) identical(value$id, input$template), shown$templates)
    if (length(item) != 1L) return()
    chunks <- (item[[1L]]$body %||% list())$chunks %||% list()
    for (i in seq_along(chunks)) {
      local_i <- i; chunk <- chunks[[i]]; prefix <- paste0("chunk_card_", local_i, "_")
      if (!identical(chunk$type, "hierarchical_summary")) {
        output[[paste0(prefix, "rows")]] <- DT::renderDT({
          rows <- chunk$rows %||% list()
          if (!length(rows)) return(data.frame())
          data.frame(id=vapply(rows, function(x) x$id %||% "", character(1)),
                     type=vapply(rows, function(x) x$type %||% "", character(1)),
                     label=vapply(rows, function(x) x$label %||% "", character(1)),
                     indent_level=vapply(rows, function(x) as.integer(x$indent_level %||% 0L), integer(1)),
                     stringsAsFactors=FALSE)
        }, editable = TRUE, rownames = FALSE, selection = "single")
        for (r in seq_along(chunk$rows %||% list())) {
          local_r <- r
          output[[paste0(prefix, "stats_", local_r)]] <- DT::renderDT({
            stats <- (chunk$rows[[local_r]]$statistics %||% list())
            if (!length(stats)) return(data.frame())
            data.frame(id=vapply(stats, function(x) x$id %||% "", character(1)),
                       digits=vapply(stats, function(x) as.character(x$digits %||% ""), character(1)),
                       stringsAsFactors=FALSE)
          }, editable = TRUE, rownames = FALSE, selection = "single")
        }
      } else {
        output[[paste0(prefix, "levels")]] <- DT::renderDT({
          levels <- chunk$levels %||% list(); if (!length(levels)) return(data.frame())
          level_depth <- function(j, seen = integer()) { p <- levels[[j]]$parent_level %||% ""; if (!nzchar(p) || !(p %in% vapply(levels, function(x) x$id %||% "", character(1))) || j %in% seen) return(0L); pi <- match(p, vapply(levels, function(x) x$id %||% "", character(1))); 1L + level_depth(pi, c(seen, j)) }
          data.frame(id=vapply(levels, function(x) x$id %||% "", character(1)),
                     variable=vapply(seq_along(levels), function(j) paste0(strrep("  ", level_depth(j)), levels[[j]]$variable %||% ""), character(1)),
                     label_variable=vapply(levels, function(x) x$label_variable %||% "", character(1)),
                     order_variable=vapply(levels, function(x) x$order_variable %||% "", character(1)),
                     order_direction=vapply(levels, function(x) x$order_direction %||% "", character(1)),
                     node_role=vapply(levels, function(x) x$node_role %||% "", character(1)),
                     node_analysis_id=vapply(levels, function(x) x$node_analysis_id %||% "", character(1)),
                     missing_policy=vapply(levels, function(x) x$missing_policy %||% "", character(1)),
                     missing_label=vapply(levels, function(x) x$missing_label %||% "", character(1)),
                     parent_level=vapply(levels, function(x) x$parent_level %||% "", character(1)),
                     stringsAsFactors=FALSE)
        }, editable = TRUE, rownames = FALSE, selection = "single")
        output[[paste0(prefix, "level_parent_ui")]] <- renderUI({
          levels <- chunk$levels %||% list(); ids <- vapply(levels, function(x) x$id %||% "", character(1L))
          tagList(lapply(seq_along(levels), function(j) {
            parent_ids <- ids[seq_len(max(0L, j - 1L))]
            choices <- setNames(c("", parent_ids), c("", parent_ids))
            selectInput(paste0(prefix, "parent_level_", j), paste("Parent for", ids[[j]]),
                        choices = choices, selected = levels[[j]]$parent_level %||% "")
          }))
        })
        output[[paste0(prefix, "blocks")]] <- DT::renderDT({
          blocks <- chunk$analysis_blocks %||% list(); if (!length(blocks)) return(data.frame())
          data.frame(id=vapply(blocks, function(x) x$id %||% "", character(1)),
                     anchor_level=vapply(blocks, function(x) x$anchor_level %||% "", character(1)),
                     placement=vapply(blocks, function(x) x$placement %||% "", character(1)),
                     type=vapply(blocks, function(x) x$type %||% "", character(1)),
                     counting_unit=vapply(blocks, function(x) x$counting_unit %||% "", character(1)),
                     analysis_variable=vapply(blocks, function(x) x$analysis_variable %||% "", character(1)),
                     denominator_scope=vapply(blocks, function(x) x$denominator$scope %||% "", character(1)),
                     denominator_unit=vapply(blocks, function(x) x$denominator$unit %||% "", character(1)),
                     denominator_variable=vapply(blocks, function(x) x$denominator$variable %||% "", character(1)),
                     denominator_expression=vapply(blocks, function(x) x$denominator$expression %||% "", character(1)),
                     stringsAsFactors=FALSE)
        }, editable = TRUE, rownames = FALSE, selection = "single")
        output[[paste0(prefix, "block_rows_ui")]] <- renderUI({
          blocks <- chunk$analysis_blocks %||% list()
          if (!length(blocks)) return(NULL)
          tagList(lapply(seq_along(blocks), function(b) {
            tagList(h5(paste("Rows for analysis block", b, blocks[[b]]$id %||% "")),
                    actionButton(paste0(prefix, "block_", b, "_row_new"), "Add row"),
                    actionButton(paste0(prefix, "block_", b, "_row_delete"), "Delete row"),
                    actionButton(paste0(prefix, "block_", b, "_row_up"), "Move row up"),
                    actionButton(paste0(prefix, "block_", b, "_row_down"), "Move row down"),
                    DTOutput(paste0(prefix, "block_", b, "_rows")),
                    uiOutput(paste0(prefix, "block_", b, "_stats_ui")))
          }))
        })
        for (b in seq_along(chunk$analysis_blocks %||% list())) {
          local_b <- b
          output[[paste0(prefix, "block_", local_b, "_rows")]] <- DT::renderDT({
            rows <- chunk$analysis_blocks[[local_b]]$rows %||% list()
            if (!length(rows)) return(data.frame())
            data.frame(id=vapply(rows, function(x) x$id %||% "", character(1)),
                       type=vapply(rows, function(x) x$type %||% "", character(1)),
                       label=vapply(rows, function(x) x$label %||% "", character(1)),
                       indent_level=vapply(rows, function(x) as.integer(x$indent_level %||% 0L), integer(1)),
                       stringsAsFactors=FALSE)
          }, editable=TRUE, rownames=FALSE, selection="single")
          output[[paste0(prefix, "block_", local_b, "_stats_ui")]] <- renderUI({
            rows <- chunk$analysis_blocks[[local_b]]$rows %||% list(); if (!length(rows)) return(NULL)
            tagList(lapply(seq_along(rows), function(rr) tagList(h6(paste("Statistics for block row", rr)), uiOutput(paste0(prefix, "block_", local_b, "_stats_", rr, "_controls")), DTOutput(paste0(prefix, "block_", local_b, "_stats_", rr)))))
          })
          for (rr in seq_along(chunk$analysis_blocks[[local_b]]$rows %||% list())) {
            local_rr <- rr
            output[[paste0(prefix, "block_", local_b, "_stats_", local_rr)]] <- DT::renderDT({
              st <- chunk$analysis_blocks[[local_b]]$rows[[local_rr]]$statistics %||% list(); if (!length(st)) return(data.frame())
              data.frame(id=vapply(st, function(x) x$id %||% "", character(1)), digits=vapply(st, function(x) as.character(x$digits %||% ""), character(1)), stringsAsFactors=FALSE)
            }, editable=TRUE, rownames=FALSE, selection="single")
            output[[paste0(prefix, "block_", local_b, "_stats_", local_rr, "_controls")]] <- renderUI({
              tagList(actionButton(paste0(prefix, "block_", local_b, "_stats_", local_rr, "_new"), "Add statistic"),
                      actionButton(paste0(prefix, "block_", local_b, "_stats_", local_rr, "_delete"), "Delete statistic"),
                      actionButton(paste0(prefix, "block_", local_b, "_stats_", local_rr, "_up"), "Move statistic up"),
                      actionButton(paste0(prefix, "block_", local_b, "_stats_", local_rr, "_down"), "Move statistic down"))
            })
          }
        }
      }
    }
  })

  # Card-level DT edits write directly into the active template draft.
  observe({
    req(input$template)
    shown <- if (!is.null(workspace()$active_draft)) workspace_overlay_active_draft(workspace()) else workspace()
    item <- Filter(function(x) identical(x$id, input$template), shown$templates); if (length(item) != 1L) return()
    chunks <- item[[1L]]$body$chunks %||% list()
    observer_key <- paste(input$template, paste(vapply(chunks, function(x) x$id %||% "", character(1L)), collapse = "|"), sep = "::")
    if (identical(session_state$template_observer_key, observer_key)) return()
    session_state$template_observer_key <- observer_key
    for (i in seq_along(chunks)) {
      p <- paste0("chunk_card_", i, "_")
      observeEvent(input[[paste0(p, "rows_cell_edit")]], {
        info <- input[[paste0(p, "rows_cell_edit")]]; if (is.null(info)) return()
        begin_edit("template", input$template); if (is.null(draft_target())) return()
        d <- workspace_draft_value(workspace()); if (info$row > length(d$body$chunks[[i]]$rows %||% list())) return()
        if (info$col == 3L) d$body$chunks[[i]]$rows[[info$row]]$label <- as.character(info$value)
        if (info$col == 4L) d$body$chunks[[i]]$rows[[info$row]]$indent_level <- as.integer(info$value)
        workspace(workspace_set_draft(workspace(), d)$workspace)
      }, ignoreInit = TRUE)
      for (r in seq_along(chunks[[i]]$rows %||% list())) {
        local_r <- r
        observeEvent(input[[paste0(p, "stats_", local_r, "_cell_edit")]], {
          info <- input[[paste0(p, "stats_", local_r, "_cell_edit")]]; if (is.null(info)) return()
          begin_edit("template", input$template); if (is.null(draft_target())) return()
          d <- workspace_draft_value(workspace()); st <- d$body$chunks[[i]]$rows[[local_r]]$statistics %||% list()
          if (info$row > length(st)) return()
          if (info$col == 2L) st[[info$row]]$digits <- suppressWarnings(as.numeric(info$value))
          d$body$chunks[[i]]$rows[[local_r]]$statistics <- st
          workspace(workspace_set_draft(workspace(), d)$workspace)
        }, ignoreInit = TRUE)
      }
      if (identical(chunks[[i]]$type, "hierarchical_summary")) {
        for (lv_i in seq_along(chunks[[i]]$levels %||% list())) {
          local_lv_i <- lv_i
          observeEvent(input[[paste0(p, "parent_level_", local_lv_i)]], {
            begin_edit("template", input$template); if (is.null(draft_target())) return()
            d <- workspace_draft_value(workspace()); lv <- d$body$chunks[[i]]$levels %||% list(); if (local_lv_i > length(lv)) return()
            val <- input[[paste0(p, "parent_level_", local_lv_i)]]; lv[[local_lv_i]]$parent_level <- if (nzchar(val %||% "")) val else NULL
            d$body$chunks[[i]]$levels <- lv; workspace(workspace_set_draft(workspace(), d)$workspace)
          }, ignoreInit=TRUE)
        }
        observeEvent(input[[paste0(p, "levels_cell_edit")]], {
          info <- input[[paste0(p, "levels_cell_edit")]]; if (is.null(info)) return()
          begin_edit("template", input$template); if (is.null(draft_target())) return()
          d <- workspace_draft_value(workspace()); lv <- d$body$chunks[[i]]$levels %||% list(); if (info$row > length(lv)) return()
          fields <- c("variable","label_variable","order_variable","order_direction","node_role","node_analysis_id","missing_policy","missing_label")
          if (info$col >= 2L && info$col <= 9L) lv[[info$row]][[fields[[info$col - 1L]]]] <- as.character(info$value)
          if (info$col == 10L) lv[[info$row]]$parent_level <- as.character(info$value)
          d$body$chunks[[i]]$levels <- lv; workspace(workspace_set_draft(workspace(), d)$workspace)
        }, ignoreInit = TRUE)
        observeEvent(input[[paste0(p, "blocks_cell_edit")]], {
          info <- input[[paste0(p, "blocks_cell_edit")]]; if (is.null(info)) return()
          begin_edit("template", input$template); if (is.null(draft_target())) return()
          d <- workspace_draft_value(workspace()); bl <- d$body$chunks[[i]]$analysis_blocks %||% list(); if (info$row > length(bl)) return()
          fields <- c("anchor_level","placement","type","counting_unit","analysis_variable")
          if (info$col >= 2L && info$col <= 6L) bl[[info$row]][[fields[[info$col - 1L]]]] <- as.character(info$value)
          if (info$col >= 7L && info$col <= 10L) {
            bl[[info$row]]$denominator <- bl[[info$row]]$denominator %||% list()
            df <- c("scope", "unit", "variable", "expression")
            bl[[info$row]]$denominator[[df[[info$col - 6L]]]] <- as.character(info$value)
          }
          d$body$chunks[[i]]$analysis_blocks <- bl; workspace(workspace_set_draft(workspace(), d)$workspace)
        }, ignoreInit = TRUE)
        observeEvent(input[[paste0(p, "block_type")]], {
          sel <- input[[paste0(p, "blocks_rows_selected")]]
          if (!length(sel)) return()
          begin_edit("template", input$template); if (is.null(draft_target())) return()
          d <- workspace_draft_value(workspace()); bl <- d$body$chunks[[i]]$analysis_blocks %||% list()
          if (sel[[1L]] > length(bl)) return()
          new_type <- input[[paste0(p, "block_type")]]
          bl[[sel[[1L]]] ]$type <- new_type
          if (new_type == "continuous_summary") {
            bl[[sel[[1L]]] ]$analysis_variable <- bl[[sel[[1L]]] ]$analysis_variable %||% "VALUE"
            bl[[sel[[1L]]] ]$denominator <- NULL
          } else {
            bl[[sel[[1L]]] ]$denominator <- bl[[sel[[1L]]] ]$denominator %||% list(scope="current_group", unit="record")
            bl[[sel[[1L]]] ]$analysis_variable <- NULL
          }
          d$body$chunks[[i]]$analysis_blocks <- bl
          workspace(workspace_set_draft(workspace(), d)$workspace)
        }, ignoreInit = TRUE)
      }
      # Collection controls use the selected row (DT is 1-based) and mutate
      # the template draft. IDs are generated from the parent and position.
      collection_action <- function(collection, action, selected, make_item) {
        begin_edit("template", input$template); if (is.null(draft_target())) return()
        d <- workspace_draft_value(workspace()); current <- d$body$chunks[[i]][[collection]] %||% list()
        if (action == "new") current[[length(current) + 1L]] <- make_item(length(current) + 1L)
        if (action == "delete" && length(selected) && selected[[1L]] <= length(current)) current <- current[-selected[[1L]]]
        if (action %in% c("up", "down") && length(selected) && selected[[1L]] <= length(current)) {
          j <- selected[[1L]] + if (action == "up") -1L else 1L
          if (j >= 1L && j <= length(current)) { z <- current[[selected[[1L]]]]; current[[selected[[1L]]]] <- current[[j]]; current[[j]] <- z }
        }
        d$body$chunks[[i]][[collection]] <- current
        workspace(workspace_set_draft(workspace(), d)$workspace)
      }
      observeEvent(input[[paste0(p, "row_new")]], collection_action("rows", "new", integer(), function(n) {
        typ <- if (grepl("categorical", chunks[[i]]$type %||% "")) "analysis" else "analysis"
        list(id=paste0(chunks[[i]]$id, "_", sprintf("%03d", n)), type=typ, label="New row", indent_level=0L,
             condition=if (grepl("categorical", chunks[[i]]$type %||% "")) "1" else NULL,
             statistics=if (grepl("categorical", chunks[[i]]$type %||% "")) list(list(id="n", digits=0L), list(id="pct", digits=1L)) else list(list(id="n", digits=0L)), cell_format=list())
      }), ignoreInit=TRUE)
      observeEvent(input[[paste0(p, "row_delete")]], collection_action("rows", "delete", input[[paste0(p, "rows_rows_selected")]], identity), ignoreInit=TRUE)
      observeEvent(input[[paste0(p, "row_up")]], collection_action("rows", "up", input[[paste0(p, "rows_rows_selected")]], identity), ignoreInit=TRUE)
      observeEvent(input[[paste0(p, "row_down")]], collection_action("rows", "down", input[[paste0(p, "rows_rows_selected")]], identity), ignoreInit=TRUE)
      for (r in seq_along(chunks[[i]]$rows %||% list())) {
        local_r <- r
        observeEvent(input[[paste0(p, "stats_new_", local_r)]], {
          begin_edit("template", input$template); if (is.null(draft_target())) return()
          d <- workspace_draft_value(workspace()); st <- d$body$chunks[[i]]$rows[[local_r]]$statistics %||% list()
          st[[length(st) + 1L]] <- list(id = "n", digits = 0L)
          d$body$chunks[[i]]$rows[[local_r]]$statistics <- st
          workspace(workspace_set_draft(workspace(), d)$workspace)
        }, ignoreInit=TRUE)
        observeEvent(input[[paste0(p, "stats_delete_", local_r)]], {
          begin_edit("template", input$template); if (is.null(draft_target())) return(); d <- workspace_draft_value(workspace()); st <- d$body$chunks[[i]]$rows[[local_r]]$statistics %||% list(); s <- input[[paste0(p, "stats_", local_r, "_rows_selected")]]; if (length(s) && s[[1L]] <= length(st)) { d$body$chunks[[i]]$rows[[local_r]]$statistics <- st[-s[[1L]]]; workspace(workspace_set_draft(workspace(), d)$workspace) }
        }, ignoreInit=TRUE)
        for (act in c("up", "down")) observeEvent(input[[paste0(p, "stats_", act, "_", local_r)]], {
          s <- input[[paste0(p, "stats_", local_r, "_rows_selected")]]; if (!length(s)) return()
          begin_edit("template", input$template); if (is.null(draft_target())) return(); d <- workspace_draft_value(workspace()); st <- d$body$chunks[[i]]$rows[[local_r]]$statistics %||% list(); j <- s[[1L]] + if (act == "up") -1L else 1L; if (j >= 1L && j <= length(st)) { z <- st[[s[[1L]]]]; st[[s[[1L]]]] <- st[[j]]; st[[j]] <- z; d$body$chunks[[i]]$rows[[local_r]]$statistics <- st; workspace(workspace_set_draft(workspace(), d)$workspace) }
        }, ignoreInit=TRUE)
      }
      if (identical(chunks[[i]]$type, "hierarchical_summary")) {
        for (kind in c("level", "block")) {
          coll <- if (kind == "level") "levels" else "analysis_blocks"
          for (act in c("new", "delete", "up", "down")) {
            observeEvent(input[[paste0(p, kind, "_", act)]], {
              sel <- input[[paste0(p, coll, "_rows_selected")]]
              maker <- if (kind == "level") function(n) list(id=paste0(chunks[[i]]$id, "_level_", sprintf("%03d", n)), parent_level=if (length(chunks[[i]]$levels)) chunks[[i]]$levels[[length(chunks[[i]]$levels)]]$id else NULL, variable="VAR", order_variable="VAR", order_direction="asc", node_role="label", missing_policy="exclude") else function(n) { bt <- input[[paste0(p, "block_type")]] %||% "continuous_summary"; z <- list(id=paste0(chunks[[i]]$id, "_analysis_", sprintf("%03d", n)), anchor_level=(chunks[[i]]$levels[[1L]]$id %||% "level_001"), placement="same_row", type=bt, counting_unit="record", rows=list(list(id="row_001", type="analysis", label="New row", indent_level=0L, statistics=list(list(id="n", digits=0L)), cell_format=list()))); if (bt == "continuous_summary") z$analysis_variable <- "VALUE" else z$denominator <- list(scope="current_group", unit="record"); z }
              collection_action(coll, act, sel, maker)
            }, ignoreInit=TRUE)
          }
        }
        for (b in seq_along(chunks[[i]]$analysis_blocks %||% list())) {
          local_b <- b
          for (act in c("new", "delete", "up", "down")) observeEvent(input[[paste0(p, "block_", local_b, "_row_", act)]], {
            begin_edit("template", input$template); if (is.null(draft_target())) return()
            d <- workspace_draft_value(workspace()); rows <- d$body$chunks[[i]]$analysis_blocks[[local_b]]$rows %||% list()
            sel <- input[[paste0(p, "block_", local_b, "_rows_rows_selected")]]
            if (act == "new") rows[[length(rows) + 1L]] <- list(id=paste0(d$body$chunks[[i]]$analysis_blocks[[local_b]]$id, "_", sprintf("%03d", length(rows)+1L)), type="analysis", label="New row", indent_level=0L, statistics=list(list(id="n", digits=0L)), cell_format=list())
            if (act == "delete" && length(sel) && sel[[1L]] <= length(rows)) rows <- rows[-sel[[1L]]]
            if (act %in% c("up", "down") && length(sel) && sel[[1L]] <= length(rows)) { j <- sel[[1L]] + if (act == "up") -1L else 1L; if (j >= 1L && j <= length(rows)) { z <- rows[[sel[[1L]]]]; rows[[sel[[1L]]]] <- rows[[j]]; rows[[j]] <- z } }
            d$body$chunks[[i]]$analysis_blocks[[local_b]]$rows <- rows
            workspace(workspace_set_draft(workspace(), d)$workspace)
          }, ignoreInit=TRUE)
          for (rr in seq_along(chunks[[i]]$analysis_blocks[[local_b]]$rows %||% list())) {
            local_rr <- rr
            for (act in c("new", "delete", "up", "down")) observeEvent(input[[paste0(p, "block_", local_b, "_stats_", local_rr, "_", act)]], {
              begin_edit("template", input$template); if (is.null(draft_target())) return()
              d <- workspace_draft_value(workspace()); st <- d$body$chunks[[i]]$analysis_blocks[[local_b]]$rows[[local_rr]]$statistics %||% list(); sel <- input[[paste0(p, "block_", local_b, "_stats_", local_rr, "_rows_selected")]]
              if (act == "new") st[[length(st)+1L]] <- list(id="n", digits=0L)
              if (act == "delete" && length(sel) && sel[[1L]] <= length(st)) st <- st[-sel[[1L]]]
              if (act %in% c("up", "down") && length(sel) && sel[[1L]] <= length(st)) { j <- sel[[1L]] + if (act == "up") -1L else 1L; if (j >= 1L && j <= length(st)) { z <- st[[sel[[1L]]]]; st[[sel[[1L]]]] <- st[[j]]; st[[j]] <- z } }
              d$body$chunks[[i]]$analysis_blocks[[local_b]]$rows[[local_rr]]$statistics <- st; workspace(workspace_set_draft(workspace(), d)$workspace)
            }, ignoreInit=TRUE)
          }
        }
      }
    }
  })

  update_template_chunk_field <- function(index, field, value) {
    if (isTRUE(session_state$suppress_selection) || is.null(input$template)) return()
    if (is.null(value)) return()
    shown <- if (!is.null(workspace()$active_draft)) workspace_overlay_active_draft(workspace()) else workspace()
    item <- Filter(function(x) identical(x$id, input$template), shown$templates)
    if (length(item) != 1L) return()
    chunks <- item[[1L]]$body$chunks %||% list(); if (index > length(chunks)) return()
    old <- chunks[[index]][[field]] %||% ""
    if (identical(as.character(old), as.character(value))) return()
    begin_edit("template", input$template); if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$body$chunks[[index]][[field]] <- value
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }
  observe({
    req(input$template)
    shown <- if (!is.null(workspace()$active_draft)) workspace_overlay_active_draft(workspace()) else workspace()
    item <- Filter(function(x) identical(x$id, input$template), shown$templates); if (length(item) != 1L) return()
    chunks <- item[[1L]]$body$chunks %||% list()
    for (i in seq_along(chunks)) {
      p <- paste0("chunk_card_", i, "_"); ch <- chunks[[i]]
      update_template_chunk_field(i, "source_data", input[[paste0(p, "source_data")]])
      update_template_chunk_field(i, "filter", if (nzchar(input[[paste0(p, "filter")]] %||% "")) input[[paste0(p, "filter")]] else NULL)
      if (identical(ch$type, "continuous_summary")) update_template_chunk_field(i, "analysis_variable", input[[paste0(p, "analysis_variable")]])
      if (ch$type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
        den <- ch$denominator %||% list()
        vals <- list(scope = input[[paste0(p, "den_scope")]],
                     unit = input[[paste0(p, "den_unit")]],
                     variable = input[[paste0(p, "den_variable")]],
                     expression = input[[paste0(p, "den_expression")]])
        vals <- vals[!vapply(vals, is.null, logical(1L))]
        vals <- vals[nzchar(as.character(unlist(vals)))]
        # Dynamic UI inputs fire while cards are rebuilt.  Only create/update
        # a draft when the denominator actually differs from the displayed
        # metadata, and guard the chunk index against a stale observer.
        old_den <- den[names(vals)]
        changed <- !identical(as.character(old_den), as.character(vals))
        if (changed) {
          begin_edit("template", input$template)
          if (!is.null(draft_target())) {
            d <- workspace_draft_value(workspace())
            if (length(d$body$chunks %||% list()) >= i) {
              d$body$chunks[[i]]$denominator <- vals
              workspace(workspace_set_draft(workspace(), d)$workspace)
            }
          }
        }
      }
    }
  })
  observe_chunk_card <- function(index, field) {
    observeEvent(input[[paste0("chunk_", field, "_", index)]], {
      if (isTRUE(session_state$suppress_selection)) return()
      item <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
      if (length(item) != 1L) return()
      chunks <- item[[1L]]$body$chunks %||% list()
      if (index > length(chunks)) return()
      begin_edit("template", input$template)
      if (is.null(draft_target())) return()
      draft <- workspace_draft_value(workspace()); draft$body$chunks[[index]][[field]] <- input[[paste0("chunk_", field, "_", index)]]
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }, ignoreInit = TRUE)
  }
  observeEvent(input$template, {
    item <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
    if (length(item) != 1L) return()
    chunks <- (item[[1L]]$body %||% list())$chunks %||% list()
    if (!is.list(chunks)) return()
    for (index in seq_along(chunks)) {
      observe_chunk_card(index, "source_data")
      observe_chunk_card(index, "filter")
    }
  }, ignoreInit = TRUE)

  begin_edit <- function(type, id) {
    if (is.null(draft_target()) && nzchar(id %||% "")) {
      begun <- workspace_begin_draft(session_state$workspace, type, id)
      if (begun$passed) {
        session_state$workspace <- begun$workspace
        draft_target(TRUE)
        draft_identity(list(type = type, id = id))
      }
    }
  }

  observeEvent(input$header, {
    if (isTRUE(session_state$suppress_selection)) return()
    if (!is.null(draft_target()) && !identical(draft_identity(), list(type = "header", id = input$header))) { request_switch("header", input$header, "header"); return() }
    item <- Filter(function(value) identical(value$id, input$header), session_state$workspace$headers)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "header_source_data", value = item[[1L]]$source_data)
      columns <- item[[1L]]$columns %||% list()
      if (length(columns) == 0L) return()
      column <- columns[[1L]]
      updateTextInput(session, "header_column_label", value = column$label)
      updateTextInput(session, "header_column_condition", value = column$condition)
    }
  }, ignoreInit = FALSE)

  observeEvent(input$table, {
    if (isTRUE(session_state$suppress_selection)) return()
    if (!is.null(draft_target()) && !identical(selected_target(), input$table)) {
      request_switch("table", input$table, "table")
      return()
    }
    selected_target(input$table)
    item <- Filter(function(value) identical(value$id, input$table), session_state$workspace$tables)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "table_population_id", value = item[[1L]]$population_id)
      updateTextInput(session, "table_header_id", value = item[[1L]]$header_id)
      updateTextInput(session, "table_template_id", value = item[[1L]]$template_id)
      custom_code <- item[[1L]]$custom_code %||% list()
      updateTextAreaInput(session, "table_custom_before", value = custom_code$before %||% "")
      updateTextAreaInput(session, "table_custom_after", value = custom_code$after %||% "")
    }
  }, ignoreInit = FALSE)
  observeEvent(input$table_population_id, {
    if (isTRUE(session_state$suppress_selection)) return()
    current <- Filter(function(value) identical(value$id, input$table), workspace()$tables)
    if (length(current) == 1L && identical(current[[1L]]$population_id, input$table_population_id)) return()
    begin_edit("table", input$table)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$population_id <- input$table_population_id
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$table_header_id, {
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$header_id <- input$table_header_id
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$table_template_id, {
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$template_id <- input$table_template_id
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$table_custom_before, {
    if (isTRUE(session_state$suppress_selection)) return()
    begin_edit("table", input$table)
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$custom_code <- draft$custom_code %||% list(); draft$custom_code$before <- if (nzchar(input$table_custom_before)) input$table_custom_before else NULL
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$table_custom_after, {
    if (isTRUE(session_state$suppress_selection)) return()
    begin_edit("table", input$table)
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$custom_code <- draft$custom_code %||% list(); draft$custom_code$after <- if (nzchar(input$table_custom_after)) input$table_custom_after else NULL
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$header_source_data, {
    if (isTRUE(session_state$suppress_selection)) return()
    current <- Filter(function(value) identical(value$id, input$header), workspace()$headers)
    if (length(current) == 1L && identical(current[[1L]]$source_data, input$header_source_data)) return()
    begin_edit("header", input$header)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$source_data <- input$header_source_data
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$header_column_label, {
    if (isTRUE(session_state$suppress_selection)) return()
    begin_edit("header", input$header)
    if (!is.null(draft_target())) { draft <- workspace_draft_value(workspace()); if (length(draft$columns %||% list()) == 0L) return(); draft$columns[[1L]]$label <- input$header_column_label; workspace(workspace_set_draft(workspace(), draft)$workspace) }
  }, ignoreInit = TRUE)
  observeEvent(input$header_column_condition, {
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$columns[[1L]]$condition <- input$header_column_condition; workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  output$header_columns_table <- DT::renderDT({
    item <- Filter(function(value) identical(value$id, input$header), session_state$workspace$headers)
    if (length(item) != 1L) return(data.frame())
    columns <- item[[1L]]$columns %||% list()
    if (length(columns) == 0L) return(data.frame())
    data.frame(id = vapply(columns, `[[`, "", "id"),
               label = vapply(columns, `[[`, "", "label"),
               condition = vapply(columns, `[[`, "", "condition"),
               display_order = vapply(columns, `[[`, integer(1L), "display_order"),
               width = vapply(columns, `[[`, numeric(1L), "width"),
               alignment = vapply(columns, `[[`, "", "alignment"),
               stringsAsFactors = FALSE)
  }, editable = TRUE, rownames = FALSE, selection = "single")
  output$header_spanning_table <- DT::renderDT({
    item <- Filter(function(value) identical(value$id, input$header), workspace()$headers)
    if (length(item) != 1L) return(data.frame())
    spans <- item[[1L]]$spanning_headers %||% list()
    if (!length(spans)) return(data.frame(id=character(), level=integer(), label=character()))
    data.frame(id=vapply(spans, `[[`, "", "id"), level=vapply(spans, `[[`, integer(1L), "level"), label=vapply(spans, `[[`, "", "label"), stringsAsFactors=FALSE)
  }, editable=TRUE, rownames=FALSE, selection="single")
  observeEvent(input$header_spanning_table_cell_edit, {
    info <- input$header_spanning_table_cell_edit
    if (is.null(info)) return()
    begin_edit("header", input$header)
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); spans <- draft$spanning_headers %||% list()
    if (!length(spans) || info$row > length(spans)) return()
    if (info$col == 2L) spans[[info$row]]$level <- as.integer(info$value)
    if (info$col == 3L) spans[[info$row]]$label <- as.character(info$value)
    draft$spanning_headers <- spans
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  })
  observeEvent(input$header_columns_table_cell_edit, {
    info <- input$header_columns_table_cell_edit
    if (is.null(info)) return()
    begin_edit("header", input$header)
    draft <- workspace_draft_value(workspace())
    row <- info$row; col <- info$col
    if (col == 2L) draft$columns[[row]]$label <- as.character(info$value)
    if (col == 3L) draft$columns[[row]]$condition <- as.character(info$value)
    if (col == 4L) draft$columns[[row]]$display_order <- as.integer(info$value)
    if (col == 5L) draft$columns[[row]]$width <- as.numeric(info$value)
    if (col == 6L) draft$columns[[row]]$alignment <- as.character(info$value)
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  })
  observeEvent(input$header_save, {
    result <- application_save_draft(workspace())
    if (result$passed) { workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace); status("Header saved.") } else showNotification(error_text(result$errors), type="error")
  })
  observeEvent(input$header_discard, {
    result <- application_discard_draft(workspace()); workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace); status("Header changes discarded.")
  })
  observeEvent(input$header_column_new, {
    begin_edit("header", input$header); if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); n <- length(draft$columns %||% list())
    draft$columns[[n + 1L]] <- list(id=paste0("column_", n + 1L), label="New column", condition="1", display_order=n + 1L, width=1, alignment="center")
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  })
  observeEvent(input$header_column_delete, {
    info <- input$header_columns_table_rows_selected; if (!length(info)) return()
    begin_edit("header", input$header); if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$columns <- draft$columns[-info[[1L]]]
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  })
  request_delete <- function(type, id) {
    impact <- workspace_delete_impact(workspace(), type, id)
    session_state$delete_impact <- impact
    if (!isTRUE(impact$allowed)) {
      showNotification(error_text(impact$errors), type = "error")
      return()
    }
    showModal(modalDialog(
      title = "Confirm delete",
      paste("Delete", type, id, "? Affected tables:", paste(impact$affected_tables, collapse = ", ")),
      footer = tagList(modalButton("Cancel"), actionButton("confirm_delete", "Delete", class = "btn-danger"))
    ))
  }
  new_object <- function(type) {
    values <- workspace()
    if (type == "population") {
      base <- if (length(values$populations)) clone_metadata_value(values$populations[[1L]]) else list(id="population_1", label="New population", expression="1")
      base$id <- paste0("population_", length(values$populations) + 1L)
    } else if (type == "header") {
      base <- if (length(values$headers)) clone_metadata_value(values$headers[[1L]]) else list(id="header_1", source_data="adam.adsl", columns=list(list(id="overall", label="Overall", condition="1", display_order=1L, width=1, alignment="center")))
      base$id <- paste0("header_", length(values$headers) + 1L)
    } else if (type == "table") {
      if (!length(values$populations) || !length(values$headers) || !length(values$templates)) { showNotification("Create a population, header, and template first.", type="warning"); return() }
      base <- list(id=paste0("table_", length(values$tables) + 1L), population_id=values$populations[[1L]]$id, header_id=values$headers[[1L]]$id, template_id=values$templates[[1L]]$id)
    } else {
      base <- if (length(values$templates)) clone_metadata_value(values$templates[[1L]]) else list(id="template_1", body=list(stub_header="Characteristic", chunks=list()))
      base$id <- paste0("template_", length(values$templates) + 1L)
    }
    result <- workspace_begin_draft(values, type, document_id = base$id, operation = "create", value = base)
    if (result$passed) {
      workspace(result$workspace); draft_target(TRUE); draft_identity(list(type = type, id = base$id)); refresh_tables(result$workspace)
      updateSelectInput(session, type, selected = base$id); status(paste("Draft created", type, base$id))
    } else showNotification(error_text(result$errors), type="error")
  }
  observeEvent(input$population_new, new_object("population"))
  observeEvent(input$header_new, new_object("header"))
  observeEvent(input$table_new, new_object("table"))
  observeEvent(input$template_new, new_object("template"))
  observeEvent(input$population_delete, request_delete("population", input$population))
  observeEvent(input$header_delete, request_delete("header", input$header))
  observeEvent(input$table_delete, request_delete("table", input$table))
  observeEvent(input$template_delete, request_delete("template", input$template))
  observeEvent(input$confirm_delete, {
    impact <- session_state$delete_impact
    removeModal()
    if (is.null(impact)) return()
    result <- workspace_delete(workspace(), impact$target, confirm = TRUE)
    if (result$passed) { workspace(result$workspace); session_state$delete_impact <- NULL; refresh_tables(result$workspace); status("Object deleted.") }
    else status(error_text(result$errors))
  })

  observeEvent(input$template, {
    if (isTRUE(session_state$suppress_selection)) return()
    if (is.null(input$template) || !nzchar(input$template)) return()
    if (!is.null(draft_target()) && !identical(draft_identity(), list(type = "template", id = input$template))) { request_switch("template", input$template, "template"); return() }
    item <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
    if (length(item) == 1L && is.null(draft_target())) {
      body <- item[[1L]]$body %||% list()
      updateTextInput(session, "template_stub_header", value = body$stub_header %||% "")
    }
  }, ignoreInit = FALSE)
  observeEvent(input$template_stub_header, {
    if (isTRUE(session_state$suppress_selection)) return()
    current <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
    if (length(current) == 1L && identical(current[[1L]]$body$stub_header %||% "", input$template_stub_header)) return()
    begin_edit("template", input$template)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$body$stub_header <- input$template_stub_header
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)

  find_chunk <- function(values, id) {
    chunks <- unlist(lapply(values$templates, function(template) template$body$chunks %||% list()), recursive = FALSE)
    Filter(function(value) identical(value$id, id), chunks)
  }
  observeEvent(input$chunk, {
    if (is.null(input$chunk) || !nzchar(input$chunk)) return()
    item <- find_chunk(workspace(), input$chunk)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "chunk_source_data", value = item[[1L]]$source_data)
      updateTextInput(session, "chunk_filter", value = item[[1L]]$filter %||% "")
      rows <- item[[1L]]$rows %||% list()
      if (length(rows) == 0L) {
        updateTextInput(session, "chunk_row_label", value = "")
        updateTextInput(session, "chunk_statistic_id", value = "")
        updateNumericInput(session, "chunk_statistic_digits", value = NA)
        return()
      }
      row <- rows[[1L]]
      updateTextInput(session, "chunk_row_label", value = row$label %||% "")
      statistics <- row$statistics %||% list()
      statistic <- if (length(statistics) > 0L) statistics[[1L]] else list()
      updateTextInput(session, "chunk_statistic_id", value = statistic$id %||% "")
      updateNumericInput(session, "chunk_statistic_digits", value = statistic$digits %||% NA)
    }
  }, ignoreInit = FALSE)
  observeEvent(input$chunk_source_data, {
    if (isTRUE(session_state$suppress_selection)) return()
    begin_edit("chunk", input$chunk)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$source_data <- input$chunk_source_data
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_row_label, {
    if (isTRUE(session_state$suppress_selection)) return()
    begin_edit("chunk", input$chunk)
    if (!is.null(draft_target())) { draft <- workspace_draft_value(workspace()); rows <- draft$rows %||% list(); if (!length(rows)) return(); draft$rows[[1L]]$label <- input$chunk_row_label; workspace(workspace_set_draft(workspace(), draft)$workspace) }
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_statistic_id, {
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); rows <- draft$rows %||% list(); if (!length(rows) || !length(rows[[1L]]$statistics %||% list())) return(); draft$rows[[1L]]$statistics[[1L]]$id <- input$chunk_statistic_id; workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_statistic_digits, {
    if (is.null(draft_target()) || is.na(input$chunk_statistic_digits)) return()
    draft <- workspace_draft_value(workspace()); rows <- draft$rows %||% list(); if (!length(rows) || !length(rows[[1L]]$statistics %||% list())) return(); draft$rows[[1L]]$statistics[[1L]]$digits <- as.integer(input$chunk_statistic_digits); workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  output$chunk_rows_table <- DT::renderDT({
    item <- find_chunk(workspace(), input$chunk)
    if (length(item) != 1L) return(data.frame())
    rows <- item[[1L]]$rows %||% list()
    if (length(rows) == 0L) return(data.frame())
    data.frame(id = vapply(rows, `[[`, "", "id"), type = vapply(rows, `[[`, "", "type"),
               label = vapply(rows, `[[`, "", "label"),
               indent_level = vapply(rows, function(row) as.integer(row$indent_level %||% 0L), integer(1L)),
               stringsAsFactors = FALSE)
  }, editable = TRUE, rownames = FALSE, selection = "single")
  observeEvent(input$chunk_rows_table_cell_edit, {
    info <- input$chunk_rows_table_cell_edit
    if (is.null(info)) return()
    begin_edit("chunk", input$chunk)
    draft <- workspace_draft_value(workspace())
    if (info$col == 3L) draft$rows[[info$row]]$label <- as.character(info$value)
    if (info$col == 4L) draft$rows[[info$row]]$indent_level <- as.integer(info$value)
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  })
  chunk_operation <- function(operation) {
    item <- find_chunk(workspace(), input$chunk)
    if (length(item) != 1L) return()
    templates <- Filter(function(value) any(vapply(value$body$chunks %||% list(), function(chunk) identical(chunk$id, input$chunk), logical(1L))), workspace()$templates)
    if (length(templates) == 0L) return()
    template <- templates[[1L]]
    result <- switch(operation,
      add = workspace_create(workspace(), "chunk", { value <- clone_metadata_value(item[[1L]]); value$id <- paste0(input$chunk, "_new"); value }, template_id = template$id),
      delete = workspace_delete(workspace(), workspace_target("chunk", input$chunk, template_id = template$id), confirm = TRUE),
      up = workspace_move(workspace(), workspace_target("chunk", input$chunk, template_id = template$id), "up"),
      down = workspace_move(workspace(), workspace_target("chunk", input$chunk, template_id = template$id), "down"))
    if (isTRUE(result$passed)) { workspace(result$workspace); refresh_tables(result$workspace); status(paste("Chunk", operation, "completed.")) } else status(error_text(result$errors))
  }
  observeEvent(input$chunk_add, chunk_operation("add"))
  observeEvent(input$chunk_delete, chunk_operation("delete"))
  observeEvent(input$chunk_up, chunk_operation("up"))
  observeEvent(input$chunk_down, chunk_operation("down"))
  observeEvent(input$chunk_filter, {
    if (is.null(input$chunk) || !nzchar(input$chunk) || is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace())
    draft$filter <- if (nzchar(input$chunk_filter)) input$chunk_filter else NULL
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)

  observeEvent(list(input$population, workspace()), {
    if (isTRUE(session_state$suppress_selection)) return()
    if (!is.null(draft_target()) && !identical(draft_identity(), list(type = "population", id = input$population))) { request_switch("population", input$population, "population"); return() }
    id <- input$population
    if (is.null(id) || !nzchar(id)) return()
    item <- Filter(function(value) identical(value$id, id), workspace()$populations)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "population_label", value = item[[1L]]$label)
      updateTextInput(session, "population_expression", value = item[[1L]]$expression)
    }
  }, ignoreInit = FALSE)

  observeEvent(input$population_label, {
    if (isTRUE(session_state$suppress_selection)) return()
    current <- Filter(function(value) identical(value$id, input$population), workspace()$populations)
    if (length(current) == 1L && identical(current[[1L]]$label, input$population_label)) return()
    if (is.null(input$population) || !nzchar(input$population)) return()
    current <- workspace()
    if (is.null(draft_target())) {
      begun <- workspace_begin_draft(current, "population", input$population)
      if (!begun$passed) return()
      workspace(begun$workspace)
      draft_target(TRUE)
    }
    draft <- workspace_draft_value(workspace())
    draft$label <- input$population_label
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)

  observeEvent(input$population_expression, {
    if (is.null(input$population) || !nzchar(input$population) || is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace())
    draft$expression <- input$population_expression
    workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)

  observeEvent(input$save, {
    result <- application_save_draft(workspace())
    if (!result$passed) {
      status(paste("Save failed:", error_text(result$errors)))
      showNotification(status(), type = "error")
      return()
    }
    workspace(result$workspace)
    session_state$import_error <- NULL
    draft_target(NULL)
    draft_identity(NULL)
    selected_target(input$table)
    refresh_tables(result$workspace)
    status("Draft saved.")
  })

  observeEvent(input$cancel, {
    result <- application_discard_draft(workspace())
    workspace(result$workspace)
    draft_target(NULL)
    draft_identity(NULL)
    refresh_tables(result$workspace)
    status("Draft cancelled.")
  })
  observeEvent(input$table_save, {
    result <- application_save_draft(workspace())
    if (result$passed) { workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace); status("Draft saved.") }
    else { status(paste("Save failed:", error_text(result$errors))); showNotification(status(), type = "error") }
  })
  observeEvent(input$table_cancel, {
    result <- application_discard_draft(workspace()); workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace); status("Draft cancelled.")
  })
  observeEvent(input$switch_discard, {
    target <- pending_switch(); removeModal(); pending_switch(NULL)
    result <- application_discard_draft(workspace()); workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace)
    if (!is.null(target)) updateSelectInput(session, target$input_id, selected = target$id)
  })
  observeEvent(input$switch_cancel, {
    target <- pending_switch(); removeModal(); pending_switch(NULL)
    current <- draft_identity()
    if (!is.null(target) && !is.null(current) && identical(target$type, current$type)) {
      updateSelectInput(session, target$input_id, selected = current$id)
    }
  })

  import_bundle_now <- function(path) {
    result <- application_import_bundle(workspace(), readBin(path, "raw", n = file.info(path)$size))
    if (!result$passed) {
      session_state$import_error <- result$errors
      session_state$workspace_status <- "import_failed"
      status(paste("Import failed:", error_text(result$errors)))
      showNotification(status(), type = "error")
      return()
    }
    workspace(result$workspace)
    session_state$import_error <- NULL
    refresh_tables(result$workspace)
    status("Metadata imported.")
  }
  observeEvent(input$bundle, {
    req(input$bundle$datapath)
    path <- input$bundle$datapath
    has_metadata <- length(workspace()$tables) + length(workspace()$populations) + length(workspace()$headers) + length(workspace()$templates) > 0L
    if (has_metadata) {
      pending_bundle(path)
      showModal(modalDialog(title = "Replace workspace?",
        "Importing this bundle will replace the current workspace. Continue?",
        footer = tagList(modalButton("Cancel"), actionButton("confirm_import", "Import", class = "btn-warning"))))
    } else import_bundle_now(path)
  })
  observeEvent(input$confirm_import, { removeModal(); path <- pending_bundle(); pending_bundle(NULL); if (!is.null(path)) import_bundle_now(path) })

  observeEvent(input$generate, {
    if (workspace_is_dirty(workspace())) {
      status("Save or cancel the active draft before generating SAS.")
      showNotification(status(), type = "warning")
      return()
    }
    result <- application_generate_source(workspace(), input$generate_table)
    if (!result$passed) {
      status(paste("Generation failed:", error_text(result$errors)))
      showNotification(status(), type = "error")
      return()
    }
    source_text(result$value)
    session_state$generation <- list(table_id = input$generate_table, status = "generated",
                                     source_text = result$value, errors = list())
    status("SAS source generated.")
  })

  observeEvent(input$discard, {
    result <- application_discard_draft(workspace())
    workspace(result$workspace)
    status(if (result$passed) "Draft discarded." else error_text(result$errors))
  })

  output$status <- renderText(status())
  output$source <- renderText(source_text())

  output$download_bundle <- downloadHandler(
    filename = function() "metadata_bundle.zip",
    content = function(file) {
      exported <- application_export_bundle(workspace())
      if (isTRUE(exported$passed)) writeBin(exported$value$bytes, file)
    }
  )
  output$download_sas <- downloadHandler(
    filename = function() paste0(input$generate_table %||% "table", ".sas"),
    content = function(file) writeLines(source_text(), file, useBytes = TRUE)
  )
}

shinyApp(ui, server)
