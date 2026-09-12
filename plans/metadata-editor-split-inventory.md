# Metadata editor split inventory

The current `src/ui/metadata_editor.R` combines the dashboard UI, pure value
helpers, reactive editor state, top-level collection CRUD, header DT editing,
template/chunk editing, import/export, and SAS generation/download handlers.

## Current boundaries

- Lines 3-78: dashboard UI and CSS.
- Lines 80-247: pure helpers and header/row transformations.
- Lines 257-542: reactive state, editor lifecycle, navigation, dirty guard,
  and top-level collection CRUD.
- Lines 586-630: header table editing and template mutation helpers.
- Lines 650-803: template/chunk/block/row/statistic UI and dynamic observers.
- Lines 804-826: metadata import and gate handling.
- Lines 827-875: SAS generation, preview, bundle/demo export, and SAS download.
- Lines 877-end: template and chunk UI constructors.

## Constraints for extraction

The public UI IDs, `metadata_editor_ui()`, and `metadata_editor_server()` names
remain unchanged. Dynamic template handlers currently depend on shared server
closures (`input`, `output`, `session`, and reactive values), so they should be
extracted through explicit registration functions rather than copied into
independent global observers. The first implementation slice should extract
pure helpers and the UI constructor before changing server lifecycle code.

## Completed slices

- Pure helpers: `metadata_editor_helpers.R`.
- Dashboard UI and CSS: `metadata_editor_ui.R`.
- Template and chunk UI constructors: `metadata_editor_template.R`.
- Import/export handlers: `metadata_editor_import.R`.
- SAS generation and download handlers: `metadata_editor_generation.R`.
- Reactive state initialization: `metadata_editor_state.R`.
- Collection list/navigation and top-level CRUD registration:
  `metadata_editor_collections.R`.
- Header DT rendering and column operations: `metadata_editor_header.R`.

- Template dynamic output and observer registration:
  `metadata_editor_template_server.R`.
- Shared lifecycle and value collection adapter: `metadata_editor_runtime.R`.

The public `metadata_editor.R` now contains only the `metadata_editor_server()`
entry point, which delegates to the runtime adapter. All responsibility-specific
handlers are registered through an explicit session context.

## Verification

- All UI modules and `app.R` parse successfully.
- Sourcing `app.R` creates the Shiny application successfully.
- The shinytest2 interaction suite passes, including repeated Chunk movement,
  structural editing, navigation, generation, and download state.
- Focused download tests verify the generated filename and exact SAS source
  written to disk.
- The full suite reaches two pre-existing YAML BOM/CRLF failures in
  `test-yaml-codec.R`; all other suites pass.
