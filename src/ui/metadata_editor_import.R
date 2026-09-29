register_metadata_editor_import <- function(ctx) {
  input <- ctx$input
  session <- ctx$session
  workspace <- ctx$workspace
  metadata_loaded <- ctx$metadata_loaded
  pending_action <- ctx$pending_action
  source_text <- ctx$source_text
  generated_table_id <- ctx$generated_table_id
  sas_download_ready <- ctx$sas_download_ready
  status <- ctx$status
  is_guarded <- ctx$is_guarded
  show_guard <- ctx$show_guard
  clear_editor <- ctx$clear_editor
  refresh_lists <- ctx$refresh_lists
  list_ids <- ctx$list_ids
  activate_editor <- ctx$activate_editor
  editor_error_text <- ctx$editor_error_text

  import_now <- function(path) {
    bytes <- tryCatch(
      readBin(path, "raw", n = file.info(path)$size),
      error = function(e) NULL
    )
    if (is.null(bytes)) {
      showNotification("Import failed.", type = "error")
      return(invisible(NULL))
    }
    result <- application_import_bundle(workspace(), bytes)
    if (!result$passed) {
      status(paste("Import failed:", editor_error_text(result$errors)))
      showNotification(status(), type = "error")
      return(invisible(NULL))
    }
    workspace(result$workspace)
    metadata_loaded(TRUE)
    source_text("")
    generated_table_id("")
    sas_download_ready(FALSE)
    clear_editor()
    refresh_lists()
    ids <- list_ids("population")
    if (length(ids)) activate_editor("population", ids[[1L]])
    status("Metadata imported.")
    invisible(NULL)
  }
  ctx$import_now <- import_now

  observeEvent(input$upload_metadata, {
    showModal(modalDialog(
      title = "Import metadata bundle",
      fileInput("bundle", "Metadata bundle (ZIP)", accept = ".zip"),
      footer = tagList(
        actionButton("cancel_import", "Cancel"),
        actionButton("confirm_import", "Import")
      ),
      easyClose = FALSE
    ))
  })
  observeEvent(input$bundle, {
    req(input$bundle$datapath)
    path <- input$bundle$datapath
    if (is_guarded()) {
      removeModal()
      show_guard(list(kind = "import", path = path))
    } else if (metadata_loaded()) {
      pending_action(list(kind = "confirm_import", path = path))
      removeModal()
      showModal(modalDialog(
        title = "Replace workspace?",
        "Importing this bundle will replace the current workspace.",
        footer = tagList(
          actionButton("cancel_import", "Cancel"),
          actionButton("confirm_import", "Import")
        ),
        easyClose = FALSE
      ))
    } else {
      pending_action(list(kind = "confirm_import", path = path))
    }
  })
  observeEvent(input$cancel_import, {
    pending_action(NULL)
    removeModal()
  })
  observeEvent(input$confirm_import, {
    action <- pending_action()
    pending_action(NULL)
    removeModal()
    if (!is.null(action)) import_now(action$path)
  })
  # The landing page is static initial HTML; only successful import reveals the editor.
  observe({
    session$sendCustomMessage("metadata-loaded", list(loaded = metadata_loaded()))
  })
  observeEvent(input$upload_metadata_gate, {
    showModal(modalDialog(
      title = "Import metadata bundle",
      fileInput("bundle", "Metadata bundle (ZIP)", accept = ".zip"),
      footer = tagList(
        actionButton("cancel_import", "Cancel"),
        actionButton("confirm_import", "Import")
      ),
      easyClose = FALSE
    ))
  })
}
