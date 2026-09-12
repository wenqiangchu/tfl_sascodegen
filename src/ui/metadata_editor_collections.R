register_metadata_editor_collection_navigation <- function(ctx) {
  input <- ctx$input; output <- ctx$output; session <- ctx$session
  list_ids <- ctx$list_ids; editor_type <- ctx$editor_type
  editor_id <- ctx$editor_id; suppress_navigation <- ctx$suppress_navigation
  request_action <- ctx$request_action
  for (type in c("population", "header", "table", "template")) local({ t <- type
    output[[paste0(t, "_list")]] <- DT::renderDT({
      data.frame(id = list_ids(t), stringsAsFactors = FALSE)
    }, rownames = FALSE, selection = "single", options = list(dom = "t", ordering = FALSE),
    callback = JS(sprintf("table.on('click', 'tbody tr', function(){ var d=table.row(this).data(); if(d){ Shiny.setInputValue('%s_list_choice', d[0], {priority:'event'}); }});", t)))
    observeEvent(input[[paste0(t, "_list_choice")]], {
      if (suppress_navigation()) return()
      id <- input[[paste0(t, "_list_choice")]]
      if (!nzchar(id %||% "")) return()
      if (!identical(editor_id(), id)) request_action(list(kind = "switch", type = t, id = id))
    }, ignoreInit = TRUE)
  })
  observeEvent(input$main_nav, {
    if (suppress_navigation()) return()
    desired <- input$main_nav
    current <- switch(editor_type(), population = "metadata", header = "metadata", table = "table_metadata", template = "template_editor", "")
    if (!nzchar(desired %||% "") || identical(desired, current)) return()
    panel <- switch(desired, metadata = "population", table_metadata = "table", template_editor = "template", generate_sas = "generate", "")
    if (identical(panel, "generate")) request_action(list(kind = "panel", main = desired, panel = "")) else request_action(list(kind = "panel", main = desired, panel = panel))
  }, ignoreInit = TRUE)
  observeEvent(input$metadata_panel, {
    if (suppress_navigation() || !input$metadata_panel %in% c("population", "header") || identical(editor_type(), input$metadata_panel)) return()
    request_action(list(kind = "panel", main = "metadata", panel = input$metadata_panel))
  }, ignoreInit = TRUE)
}

register_metadata_editor_id_outputs <- function(ctx) {
  output <- ctx$output; editor_type <- ctx$editor_type; editor_id <- ctx$editor_id
  output$population_id_ui <- renderUI(readonly_editor_input("population_id", "ID", if (editor_type() == "population") editor_id() else ""))
  output$header_id_ui <- renderUI(readonly_editor_input("header_id", "ID", if (editor_type() == "header") editor_id() else ""))
  output$table_id_ui <- renderUI(readonly_editor_input("table_id", "ID", if (editor_type() == "table") editor_id() else ""))
  output$template_id_ui <- renderUI(readonly_editor_input("template_id", "ID", if (editor_type() == "template") editor_id() else ""))
}

metadata_editor_new_seed <- function(type, id, list_ids) {
  switch(type,
    population = list(id = id, label = "New population", expression = "1"),
    header = list(id = id, source_data = "adam.adsl", columns = list(list(
      id = "column_001", label = "Overall", condition = "1",
      display_order = 1L, width = 1, alignment = "center"))),
    table = list(id = id, population_id = list_ids("population")[[1L]],
                 header_id = list_ids("header")[[1L]],
                 template_id = list_ids("template")[[1L]]),
    template = list(id = id, body = list(stub_header = "Characteristic", chunks = list()))
  )
}

register_metadata_editor_save_discard <- function(ctx) {
  input <- ctx$input; save_active <- ctx$save_active; discard_active <- ctx$discard_active
  list_ids <- ctx$list_ids; activate_editor <- ctx$activate_editor; status <- ctx$status
  for (type in c("population", "header", "table", "template")) local({ t <- type
    observeEvent(input[[paste0(t, "_save")]], save_active(t))
    observeEvent(input[[paste0(t, "_discard")]], {
      discard_active(); ids <- list_ids(t)
      if (length(ids)) activate_editor(t, ids[[1L]])
      status("Changes discarded.")
    })
  })
}

register_metadata_editor_crud <- function(ctx) {
  input <- ctx$input; pending_action <- ctx$pending_action
  active_editor <- ctx$active_editor; editor_type <- ctx$editor_type
  editor_id <- ctx$editor_id; select_list_row <- ctx$select_list_row
  suppress_navigation <- ctx$suppress_navigation; discard_active <- ctx$discard_active
  execute_action <- ctx$execute_action; save_active <- ctx$save_active
  list_ids <- ctx$list_ids; activate_editor <- ctx$activate_editor
  status <- ctx$status; is_guarded <- ctx$is_guarded; show_guard <- ctx$show_guard
  workspace <- ctx$workspace; clear_editor <- ctx$clear_editor
  refresh_lists <- ctx$refresh_lists; generated_table_id <- ctx$generated_table_id
  sas_download_ready <- ctx$sas_download_ready; editor_error_text <- ctx$editor_error_text
  request_action <- ctx$request_action

  observeEvent(input$guard_cancel, {
    action <- pending_action(); pending_action(NULL); removeModal()
    editor <- active_editor(); if (!is.null(editor)) select_list_row(editor$document_type, editor$document_id)
    if (!is.null(action) && identical(action$kind, "panel")) {
      suppress_navigation(TRUE)
      updateTabItems(ctx$session, "main_nav", selected = switch(editor_type(), population = "metadata", header = "metadata", table = "table_metadata", template = "template_editor", "metadata"))
      if (editor_type() %in% c("population", "header")) updateTabsetPanel(ctx$session, "metadata_panel", selected = editor_type())
      ctx$session$onFlushed(function() suppress_navigation(FALSE), once = TRUE)
    }
  })
  observeEvent(input$guard_discard, {
    action <- pending_action(); pending_action(NULL); removeModal(); discard_active()
    if (!is.null(action)) execute_action(action)
  })
  for (type in c("population", "header", "table", "template")) local({ t <- type
    observeEvent(input[[paste0(t, "_save")]], save_active(t))
    observeEvent(input[[paste0(t, "_discard")]], {
      discard_active(); ids <- list_ids(t)
      if (length(ids)) activate_editor(t, ids[[1L]])
      status("Changes discarded.")
    })
    observeEvent(input[[paste0(t, "_new")]], request_action(list(kind = "new", type = t)))
    observeEvent(input[[paste0(t, "_delete")]], {
      if (identical(editor_type(), t) && nzchar(editor_id())) request_action(list(kind = "delete", type = t, id = editor_id()))
    })
  })
  observeEvent(input$cancel_new_object, { pending_action(NULL); removeModal() })
  observeEvent(input$confirm_new_object, {
    action <- pending_action(); if (is.null(action) || action$kind != "confirm_new") return()
    id <- trimws(as.character(input$new_object_id %||% "")); type <- action$type
    if (!nzchar(id)) { showNotification("ID is required.", type = "error"); return() }
    if (id %in% list_ids(type)) { showNotification("ID already exists.", type = "error"); return() }
    if (type == "table" && (!length(list_ids("population")) || !length(list_ids("header")) || !length(list_ids("template")))) {
      showNotification("Create a population, header, and template first.", type = "error"); return()
    }
    removeModal(); pending_action(NULL)
    seed <- metadata_editor_new_seed(type, id, list_ids)
    activate_editor(type, id, "create", seed); status(paste("New", type, "pending."))
  })
  observeEvent(input$cancel_delete, { pending_action(NULL); removeModal() })
  observeEvent(input$confirm_delete, {
    action <- pending_action(); if (is.null(action) || action$kind != "confirm_delete") return()
    removeModal(); pending_action(NULL)
    result <- workspace_delete_immediate(workspace(), action$target)
    if (!result$passed) { showNotification(editor_error_text(result$errors), type = "error"); return() }
    workspace(result$workspace); clear_editor(); generated_table_id(""); sas_download_ready(FALSE)
    ids <- list_ids(action$type); if (length(ids)) activate_editor(action$type, ids[[1L]])
    refresh_lists(); status("Object deleted.")
  })
}
