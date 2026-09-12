# Public Shiny server entry point. Implementation is assembled in the
# responsibility-specific modules and retained in the runtime adapter.
metadata_editor_server <- function(input, output, session) {
  metadata_editor_server_impl(input, output, session)
}
