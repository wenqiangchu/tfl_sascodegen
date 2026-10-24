library(shiny)
library(shinydashboard)
library(DT)

# Shiny evaluates app.R with the working directory set to the application
# directory, but a direct `source()` call does not, and some hosts only set the
# working directory after evaluating the file. Resolve the repository root from
# the file that is being sourced, then from the working directory, and walk
# upwards until the root markers are found so runtime asset paths stay correct.
locate_project_root <- function(candidates) {
  markers <- c("app.R", file.path("src", "core", "errors.R"))
  for (candidate in candidates) {
    directory <- if (dir.exists(candidate)) candidate else dirname(candidate)
    repeat {
      if (all(file.exists(file.path(directory, markers)))) {
        return(normalizePath(directory, mustWork = TRUE))
      }
      parent <- dirname(directory)
      if (identical(parent, directory)) {
        break
      }
      directory <- parent
    }
  }
  normalizePath(getwd(), mustWork = FALSE)
}

sourced_files <- Filter(
  function(path) is.character(path) && length(path) == 1L && nzchar(path),
  lapply(rev(sys.frames()), `[[`, "ofile")
)
project_root <- locate_project_root(c(sourced_files, getwd()))
options(tfl_sascodegen_root = project_root)
source_order <- c(
  "src/core/errors.R", "src/chunks/registry.R", "src/metadata/model.R",
  "src/metadata/yaml_codec.R", "src/metadata/workspace.R",
  "src/generator/source_generator.R", "src/generator/report_source.R",
  "src/emitters/source_input.R", "src/emitters/continuous.R",
  "src/emitters/categorical.R", "src/emitters/hierarchical.R",
  "src/emitters/precision.R", "src/emitters/result_render.R",
  "src/application/orchestration.R", "src/ui/metadata_editor_helpers.R",
  "src/ui/metadata_editor_state.R", "src/ui/metadata_editor_ui.R", "src/ui/metadata_editor_template.R",
  "src/ui/metadata_editor_collections.R", "src/ui/metadata_editor_header.R",
  "src/ui/metadata_editor_template_server.R",
  "src/ui/metadata_editor_import.R", "src/ui/metadata_editor_generation.R",
  "src/ui/metadata_editor_runtime.R", "src/ui/metadata_editor.R"
)
invisible(lapply(file.path(project_root, source_order), source, local = FALSE))

shinyApp(metadata_editor_ui(), metadata_editor_server)
