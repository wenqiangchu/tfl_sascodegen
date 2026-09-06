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
    downloadButton("download_bundle", "Download metadata"), actionButton("discard", "Discard draft")),
  dashboardBody(tabItems(
    tabItem(tabName = "metadata", tabsetPanel(
      tabPanel("Population", fluidRow(
        box(title = "Populations", width = 4, DTOutput("population_list")),
        box(title = "Population metadata", width = 8, status = "primary", solidHeader = TRUE,
          tags$div(style="display:none", selectInput("population", "Selected population", choices = character())),
          textInput("population_label", "Label"), textAreaInput("population_expression", "SAS expression", rows = 3),
          actionButton("save", "Save"), actionButton("cancel", "Cancel"), actionButton("population_delete", "Delete")))),
      tabPanel("Header", fluidRow(
        box(title = "Headers", width = 4, DTOutput("header_list")),
        box(title = "Header metadata", width = 8, status = "primary", solidHeader = TRUE,
          tags$div(style="display:none", selectInput("header", "Selected header", choices = character())),
          textInput("header_source_data", "Source data"), DTOutput("header_columns_table"),
          actionButton("header_delete", "Delete"))))),
    tabItem(tabName = "table_metadata", fluidRow(
      box(title = "Tables", width = 4, DTOutput("table_list")),
      box(title = "Table metadata", width = 8, status = "primary", solidHeader = TRUE,
        tags$div(style="display:none", selectInput("table", "Selected table", choices = character())), textInput("table_population_id", "Population ID"),
        textInput("table_header_id", "Header ID"), textInput("table_template_id", "Template ID"),
        actionButton("table_save", "Save"), actionButton("table_cancel", "Cancel"))))),
    tabItem(tabName = "template_editor", fluidRow(
      box(title = "Templates", width = 4, DTOutput("template_list")),
      box(title = "Template metadata", width = 8, status = "primary", solidHeader = TRUE,
        tags$div(style="display:none", selectInput("template", "Selected template", choices = character())), textInput("template_stub_header", "Stub header"),
        selectInput("chunk", "Selected chunk", choices = character()),
        textInput("chunk_source_data", "Source data"), textInput("chunk_filter", "Filter"),
        textInput("chunk_row_label", "First row label"), textInput("chunk_statistic_id", "First statistic ID"),
        numericInput("chunk_statistic_digits", "Statistic digits", value = NA, min = 0),
        uiOutput("chunk_cards"), actionButton("chunk_add", "Add chunk"), actionButton("chunk_delete", "Delete chunk"),
        actionButton("chunk_up", "Move up"), actionButton("chunk_down", "Move down"), DTOutput("chunk_rows_table"))))),
    tabItem(tabName = "generate_sas", box(title = "Generate SAS", width = 12, status = "success", solidHeader = TRUE,
      selectInput("generate_table", "Table", choices = character()), actionButton("generate", "Generate SAS", icon = icon("play")),
      downloadButton("download_sas", "Download SAS"), verbatimTextOutput("status"), verbatimTextOutput("source")))
  ))

server <- function(input, output, session) {
  session_state <- reactiveValues(
    workspace_status = "empty", workspace = new_empty_workspace(), import_error = NULL,
    navigation = list(active_panel = "metadata", selected_population_id = NULL,
                      selected_header_id = NULL, selected_table_id = NULL,
                      selected_template_id = NULL), active_draft = NULL,
    delete_impact = NULL,
    generation = list(table_id = NULL, status = "idle", source_text = "", errors = list())
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
      footer=tagList(actionButton("switch_save", "Save and switch"), actionButton("switch_discard", "Discard and switch"), modalButton("Cancel"))))
  }

  observeEvent(input$main_nav, {
    session_state$navigation$active_panel <- input$main_nav
  }, ignoreInit = TRUE)

  refresh_tables <- function(value) {
    session_state$workspace <- value
    session_state$workspace_status <- if (length(value$tables) > 0L) "loaded" else "empty"
    ids <- vapply(value$tables, `[[`, "", "id")
    updateSelectInput(session, "table", choices = ids,
                      selected = if (length(ids) > 0L) ids[[1L]] else character())
    updateSelectInput(session, "generate_table", choices = ids,
                      selected = if (length(ids) > 0L) ids[[1L]] else character())
    population_ids <- vapply(value$populations, `[[`, "", "id")
    updateSelectInput(session, "population", choices = population_ids,
                      selected = if (length(population_ids) > 0L) population_ids[[1L]] else character())
    header_ids <- vapply(value$headers, `[[`, "", "id")
    updateSelectInput(session, "header", choices = header_ids,
                      selected = if (length(header_ids) > 0L) header_ids[[1L]] else character())
    updateSelectInput(session, "header2", choices = header_ids,
                      selected = if (length(header_ids) > 0L) header_ids[[1L]] else character())
    template_ids <- vapply(value$templates, `[[`, "", "id")
    updateSelectInput(session, "template", choices = template_ids,
                      selected = if (length(template_ids) > 0L) template_ids[[1L]] else character())
    chunks <- unlist(lapply(value$templates, function(template) template$body$chunks %||% list()), recursive = FALSE)
    chunk_ids <- if (length(chunks) > 0L) vapply(chunks, `[[`, "", "id") else character()
    updateSelectInput(session, "chunk", choices = chunk_ids,
                      selected = if (length(chunk_ids) > 0L) chunk_ids[[1L]] else character())
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
    item <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
    if (length(item) != 1L) return(NULL)
    chunks <- item[[1L]]$body$chunks %||% list()
    tagList(lapply(seq_along(chunks), function(i) {
      chunk <- chunks[[i]]
      box(title = paste("Chunk", i, chunk$id), width = 12, status = "info", solidHeader = TRUE,
          p(strong("Type: "), chunk$type %||% ""),
          p(strong("Source data: "), chunk$source_data %||% ""),
          p(strong("Filter: "), chunk$filter %||% ""))
    }))
  })

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
    if (!is.null(draft_target()) && !identical(draft_identity(), list(type = "header", id = input$header))) { request_switch("header", input$header, "header"); return() }
    item <- Filter(function(value) identical(value$id, input$header), session_state$workspace$headers)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "header_source_data", value = item[[1L]]$source_data)
      column <- item[[1L]]$columns[[1L]]
      updateTextInput(session, "header_column_label", value = column$label)
      updateTextInput(session, "header_column_condition", value = column$condition)
    }
  }, ignoreInit = FALSE)

  observeEvent(input$table, {
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
    }
  }, ignoreInit = FALSE)
  observeEvent(input$table_population_id, {
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
  observeEvent(input$header_source_data, {
    begin_edit("header", input$header)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$source_data <- input$header_source_data
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$header_column_label, {
    begin_edit("header", input$header)
    if (!is.null(draft_target())) { draft <- workspace_draft_value(workspace()); draft$columns[[1L]]$label <- input$header_column_label; workspace(workspace_set_draft(workspace(), draft)$workspace) }
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
  observeEvent(input$population_delete, request_delete("population", input$population))
  observeEvent(input$header_delete, request_delete("header", input$header))
  observeEvent(input$confirm_delete, {
    impact <- session_state$delete_impact
    removeModal()
    if (is.null(impact)) return()
    result <- workspace_delete(workspace(), impact$target, confirm = TRUE)
    if (result$passed) { workspace(result$workspace); session_state$delete_impact <- NULL; refresh_tables(result$workspace); status("Object deleted.") }
    else status(error_text(result$errors))
  })

  observeEvent(input$template, {
    if (!is.null(draft_target()) && !identical(draft_identity(), list(type = "template", id = input$template))) { request_switch("template", input$template, "template"); return() }
    item <- Filter(function(value) identical(value$id, input$template), workspace()$templates)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "template_stub_header", value = item[[1L]]$body$stub_header %||% "")
    }
  }, ignoreInit = FALSE)
  observeEvent(input$template_stub_header, {
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
    item <- find_chunk(workspace(), input$chunk)
    if (length(item) == 1L && is.null(draft_target())) {
      updateTextInput(session, "chunk_source_data", value = item[[1L]]$source_data)
      updateTextInput(session, "chunk_filter", value = item[[1L]]$filter %||% "")
      row <- item[[1L]]$rows[[1L]]
      updateTextInput(session, "chunk_row_label", value = row$label %||% "")
      statistic <- (row$statistics %||% list())[[1L]]
      updateTextInput(session, "chunk_statistic_id", value = statistic$id %||% "")
      updateNumericInput(session, "chunk_statistic_digits", value = statistic$digits %||% NA)
    }
  }, ignoreInit = FALSE)
  observeEvent(input$chunk_source_data, {
    begin_edit("chunk", input$chunk)
    if (!is.null(draft_target())) {
      draft <- workspace_draft_value(workspace()); draft$source_data <- input$chunk_source_data
      workspace(workspace_set_draft(workspace(), draft)$workspace)
    }
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_row_label, {
    begin_edit("chunk", input$chunk)
    if (!is.null(draft_target())) { draft <- workspace_draft_value(workspace()); draft$rows[[1L]]$label <- input$chunk_row_label; workspace(workspace_set_draft(workspace(), draft)$workspace) }
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_statistic_id, {
    if (is.null(draft_target())) return()
    draft <- workspace_draft_value(workspace()); draft$rows[[1L]]$statistics[[1L]]$id <- input$chunk_statistic_id; workspace(workspace_set_draft(workspace(), draft)$workspace)
  }, ignoreInit = TRUE)
  observeEvent(input$chunk_statistic_digits, {
    if (is.null(draft_target()) || is.na(input$chunk_statistic_digits)) return()
    draft <- workspace_draft_value(workspace()); draft$rows[[1L]]$statistics[[1L]]$digits <- as.integer(input$chunk_statistic_digits); workspace(workspace_set_draft(workspace(), draft)$workspace)
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
    template <- Filter(function(value) any(vapply(value$body$chunks %||% list(), function(chunk) identical(chunk$id, input$chunk), logical(1L))), workspace()$templates)[[1L]]
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
  observeEvent(input$switch_save, {
    target <- pending_switch(); removeModal(); pending_switch(NULL)
    result <- application_save_draft(workspace())
    if (!result$passed) { showNotification(error_text(result$errors), type="error"); return() }
    workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace)
    if (!is.null(target)) updateSelectInput(session, target$input_id, selected = target$id)
  })
  observeEvent(input$switch_discard, {
    target <- pending_switch(); removeModal(); pending_switch(NULL)
    result <- application_discard_draft(workspace()); workspace(result$workspace); draft_target(NULL); draft_identity(NULL); refresh_tables(result$workspace)
    if (!is.null(target)) updateSelectInput(session, target$input_id, selected = target$id)
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
    content = function(file) writeBin(application_export_bundle(workspace())$value$bytes, file)
  )
  output$download_sas <- downloadHandler(
    filename = function() paste0(input$generate_table %||% "table", ".sas"),
    content = function(file) writeLines(source_text(), file, useBytes = TRUE)
  )
}

shinyApp(ui, server)
