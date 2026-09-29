library(shiny)
library(shinydashboard)
library(DT)

project_root <- normalizePath(getwd(), mustWork = FALSE)
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
