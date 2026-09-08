# Editor State Implementation

The Shiny adapter implements the approved active-editor model from
`active-editor-state-and-id-design.md`.

## Runtime state

Each session owns only these metadata-editor values:

- `workspace`: the saved `MetadataWorkspace` snapshot;
- `active_editor`: the current panel, document type, and document ID;
- `active_draft`: `operation`, target, and the original snapshot captured when
  the editor is activated;
- `pending_action`: the action waiting for a dirty-guard decision.

Header DT data and template card data are UI caches. They are collected only by
the editor collector at Save, Discard, Switch, Delete, Import, or Generate
boundaries. Input observers do not mirror ordinary field edits into the saved
workspace.

## Boundary behavior

Dirty state is computed by collecting the current editor value and comparing it
with `active_draft$original` using `workspace_canonical_equal()`. Reverting a
field to its original value is therefore clean. A pending create remains
`create_pending` until Save; Discard removes it without writing it to the saved
workspace. Delete is immediate after the reference check and confirmation.

The only dirty-guard choices are `Discard changes` and `Cancel`. Programmatic
UI synchronization only renders values and is not a dirty signal.

## Editor collectors

Population, header, table, and template collectors perform UI value reads,
type conversion, empty-value normalization, header span reconstruction, and
nested template expansion. Header DT displays span labels and reconstructs
canonical span IDs from contiguous label runs on Save. Template cards expose
public chunk fields, nested rows/statistics, hierarchical levels with explicit
parents, analysis block types, and structured denominators.

## Browser regression

`test/testthat/test-shinytest2.R` runs with the configured Chrome headless
flags and covers import, clean and dirty navigation, Cancel/Discard, ID-based
New, Save, Delete, Header row editing, Template card editing, and Generate
guard/source preview. Browser tests are not skipped by CRAN mode.
