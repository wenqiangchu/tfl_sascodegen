# UI-neutral application orchestration around workspace and source generation.

application_import_bundle <- function(workspace, input,
                                      registry = default_chunk_registry(),
                                      allow_dirty = FALSE) {
  workspace_import_bundle(workspace, input, registry, allow_dirty)
}

application_export_bundle <- function(workspace,
                                      registry = default_chunk_registry()) {
  workspace_export_bundle(workspace, registry)
}

application_save_draft <- function(workspace,
                                   registry = default_chunk_registry()) {
  workspace_save_draft(workspace, registry)
}

application_discard_draft <- function(workspace) {
  workspace_discard_draft(workspace)
}

application_generate_source <- function(workspace, table_id,
                                        registry = default_chunk_registry(),
                                        include_duplicate_check = TRUE,
                                        output_mode = c("report", "compare")) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  if (!is.character(table_id) || length(table_id) != 1L ||
      is.na(table_id) || !nzchar(table_id)) {
    return(list(
      passed = FALSE, value = NULL,
      errors = list(new_error_item("generation", "generation_table_invalid",
                                   "Table ID is required.", "$.table_id"))
    ))
  }
  generated <- generate_table_source(
    workspace_saved_snapshot(workspace), table_id, registry,
    include_duplicate_check = include_duplicate_check, output_mode = output_mode
  )
  list(
    passed = isTRUE(generated$passed),
    value = if (isTRUE(generated$passed)) generated$source else NULL,
    errors = generated$errors %||% list()
  )
}
