# Session-owned reactive state for the metadata editor.
# The returned environment keeps the existing state names private to one
# Shiny session while giving later UI modules an explicit dependency boundary.
new_metadata_editor_state <- function() {
  state <- new.env(parent = emptyenv())
  state$workspace <- reactiveVal(new_empty_workspace())
  state$metadata_loaded <- reactiveVal(FALSE)
  state$active_editor <- reactiveVal(NULL)
  state$active_draft <- reactiveVal(NULL)
  state$pending_action <- reactiveVal(NULL)
  state$pending_seed <- reactiveVal(NULL)
  state$header_table <- reactiveVal(NULL)
  state$template_value <- reactiveVal(NULL)
  state$row_table_cache <- reactiveVal(list())
  state$statistic_table_cache <- reactiveVal(list())
  state$status <- reactiveVal("Ready.")
  state$source_text <- reactiveVal("")
  state$generated_table_id <- reactiveVal("")
  state$sas_download_ready <- reactiveVal(FALSE)
  state$suppress_navigation <- reactiveVal(FALSE)
  state
}
