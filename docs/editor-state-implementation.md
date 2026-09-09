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

Template UI caches assign session-local `ui_uid` values to chunks,
hierarchical levels, and analysis blocks. These identities are retained across
reordering and structural edits, are used as card/editor DOM identities, and
are removed before canonical comparison or YAML/workspace save. Rows and
statistics remain position-based. Primitive chunk rows and statistics are
rendered as editable DT tables; cell edits stay in session-local caches and
are collected only at editor boundaries, then rebuilt as canonical nested
rows/statistics metadata.

The row DT is the RTF-row editor: one DT row maps to one rendered RTF row.
Visible columns are `type`, `label`, `indent_level`, `condition`,
space-separated `statistics`, space-separated positional `digits`, and
`cell_format`; the internal row ID is retained in a hidden column only for
cache and collector identity. Statistic add/delete/reorder controls are not
part of the UI; users edit statistic and digits text directly. Missing
categorical `pct` digits default to `1`, while `n` has no digits field.

Hierarchical analysis blocks use the same DT-backed rows/statistics path as
primitive chunks. Each block has independent DT input IDs and caches, so edits
and structural row/statistic actions cannot cross-contaminate sibling blocks.
Structural actions clear stale DT caches before rerendering. Save-time
reindexing regenerates positional chunk, level, analysis-block, and row IDs and
rewrites hierarchical references, including parent levels, anchor levels,
node-analysis links, and result-sort metrics.

## Boundary behavior

Dirty state is computed by collecting the current editor value and comparing it
with `active_draft$original` using `workspace_canonical_equal()`. Reverting a
field to its original value is therefore clean. A pending create remains
`create_pending` until Save; Discard removes it without writing it to the saved
workspace. Delete is immediate after the reference check and confirmation.

The only dirty-guard choices are `Discard changes` and `Cancel`. Programmatic
UI synchronization only renders values and is not a dirty signal.

Template chunk creation uses an explicit type-selection dialog. The dialog
offers `continuous_summary`, `categorical_summary_nonexclusive`,
`categorical_summary_exclusive`, and `hierarchical_summary`; confirmation
inserts the corresponding minimal structural seed into the template UI cache.
Cancel leaves the template unchanged. Chunk deletion remains an immediate
edit to the unsaved template value and has no separate confirmation dialog;
template-level Discard restores the last saved template as a whole.

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
