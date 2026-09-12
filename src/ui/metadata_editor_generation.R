generated_sas_filename <- function(table_id) {
  paste0(table_id %||% "table", ".sas")
}

write_generated_sas <- function(source, file) {
  writeLines(source, file, useBytes = TRUE)
}

register_metadata_editor_generation <- function(ctx) {
  input <- ctx$input
  output <- ctx$output
  workspace <- ctx$workspace
  source_text <- ctx$source_text
  generated_table_id <- ctx$generated_table_id
  sas_download_ready <- ctx$sas_download_ready
  status <- ctx$status
  request_action <- ctx$request_action
  editor_error_text <- ctx$editor_error_text
  is_guarded <- ctx$is_guarded

  observeEvent(input$generate_table, {
    if (!identical(as.character(input$generate_table %||% ""), generated_table_id())) {
      sas_download_ready(FALSE)
    }
  }, ignoreInit = TRUE)
  observe({
    ctx$draft_status()
    if (is_guarded()) sas_download_ready(FALSE)
  })
  generate_now <- function() {
    sas_download_ready(FALSE)
    result <- application_generate_source(workspace(), input$generate_table)
    if (!result$passed) {
      source_text("")
      generated_table_id("")
      status(paste("Generation failed:", editor_error_text(result$errors)))
      showNotification(status(), type = "error")
      return(invisible(NULL))
    }
    source_text(result$value)
    generated_table_id(as.character(input$generate_table))
    sas_download_ready(TRUE)
    status("SAS source generated.")
    invisible(NULL)
  }
  ctx$generate_now <- generate_now
  observeEvent(input$generate, request_action(list(kind = "generate")))
  output$status <- renderText(status())
  output$source <- renderText(source_text())
  output$download_bundle <- downloadHandler(
    filename = function() "metadata_bundle.zip",
    content = function(file) {
      result <- application_export_bundle(workspace())
      if (result$passed) writeBin(result$value$bytes, file)
    }
  )
  output$download_metadata_ui <- renderUI({
    button_style <- "width:180px;height:30px;padding:5px 10px;line-height:18px;font-size:12px;color:#333;background-color:#fff;border-color:#ccc;"
    if (ctx$metadata_loaded()) {
      downloadButton("download_bundle", "Download metadata", class = "btn btn-default btn-sm", style = button_style)
    } else {
      actionButton("download_metadata_disabled", "Download metadata", class = "btn btn-default btn-sm disabled", style = button_style, disabled = TRUE)
    }
  })
  output$download_demo_package <- downloadHandler(
    filename = function() "demo_metadata_package.zip",
    content = function(file) {
      staging <- tempfile("demo_package_")
      dir.create(staging)
      on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
      root <- getOption("tfl_sascodegen_root", normalizePath(getwd(), mustWork = FALSE))
      file.copy(file.path(root, "test", "fixtures", "demo_metadata.zip"), file.path(staging, "demo_metadata.zip"), overwrite = TRUE)
      guide <- file.path(staging, "user-guide.md")
      file.copy(file.path(root, "docs", "user-guide.md"), guide, overwrite = TRUE)
      zip::zipr(file, files = c("demo_metadata.zip", "user-guide.md"), root = staging, include_directories = FALSE)
    }
  )
  output$download_sas_ui <- renderUI({
    if (isTRUE(sas_download_ready()) && identical(as.character(input$generate_table %||% ""), generated_table_id())) {
      downloadButton("download_sas", "Download SAS")
    } else {
      actionButton("download_sas_disabled", "Download SAS", class = "disabled", disabled = TRUE)
    }
  })
  output$download_sas <- downloadHandler(
    filename = function() generated_sas_filename(generated_table_id()),
    content = function(file) {
      req(isTRUE(sas_download_ready()), nzchar(generated_table_id()), identical(as.character(input$generate_table %||% ""), generated_table_id()))
      write_generated_sas(source_text(), file)
    }
  )
}
