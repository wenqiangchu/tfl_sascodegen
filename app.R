library(shiny)

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

ui <- fluidPage(
  titlePanel("SAS Descriptive-Analysis Code Generator"),
  sidebarLayout(
    sidebarPanel(
      fileInput("bundle", "Metadata bundle (ZIP)", accept = ".zip"),
      actionButton("import", "Import"),
      selectInput("population", "Population", choices = character()),
      textInput("population_label", "Population label"),
      textInput("population_expression", "Population expression"),
      actionButton("save", "Save"),
      actionButton("cancel", "Cancel"),
      selectInput("table", "Table", choices = character()),
      actionButton("generate", "Generate SAS"),
      downloadButton("download_bundle", "Download metadata"),
      downloadButton("download_sas", "Download SAS"),
      actionButton("discard", "Discard draft")
    ),
    mainPanel(
      verbatimTextOutput("status"),
      verbatimTextOutput("source")
    )
  )
)

server <- function(input, output, session) {
  workspace <- reactiveVal(new_empty_workspace())
  status <- reactiveVal("Ready.")
  source_text <- reactiveVal("")
  draft_target <- reactiveVal(NULL)

  refresh_tables <- function(value) {
    ids <- vapply(value$tables, `[[`, "", "id")
    updateSelectInput(session, "table", choices = ids,
                      selected = if (length(ids) > 0L) ids[[1L]] else character())
    population_ids <- vapply(value$populations, `[[`, "", "id")
    updateSelectInput(session, "population", choices = population_ids,
                      selected = if (length(population_ids) > 0L) population_ids[[1L]] else character())
  }

  observeEvent(list(input$population, workspace()), {
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
    draft_target(NULL)
    status("Draft saved.")
  })

  observeEvent(input$cancel, {
    result <- application_discard_draft(workspace())
    workspace(result$workspace)
    draft_target(NULL)
    status("Draft cancelled.")
  })

  observeEvent(input$import, {
    req(input$bundle$datapath)
    result <- application_import_bundle(workspace(), readBin(input$bundle$datapath, "raw", n = file.info(input$bundle$datapath)$size))
    if (!result$passed) {
      status(paste("Import failed:", error_text(result$errors)))
      showNotification(status(), type = "error")
      return()
    }
    workspace(result$workspace)
    refresh_tables(result$workspace)
    status("Metadata imported.")
  })

  observeEvent(input$generate, {
    result <- application_generate_source(workspace(), input$table)
    if (!result$passed) {
      status(paste("Generation failed:", error_text(result$errors)))
      showNotification(status(), type = "error")
      return()
    }
    source_text(result$value)
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
    filename = function() paste0(input$table %||% "table", ".sas"),
    content = function(file) writeLines(source_text(), file, useBytes = TRUE)
  )
}

shinyApp(ui, server)
