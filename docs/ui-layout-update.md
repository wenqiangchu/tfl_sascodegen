# UI layout update

The Shiny dashboard now follows the approved metadata editing layout:

- Metadata is split into Population and Header tab panels.
- Each metadata area uses a left object list and a right detail editor.
- The dashboard header contains `Upload metadata`, `Download metadata`, and
  `Download demo package` actions on the right side of the application title.
- `Upload metadata` opens a modal containing the ZIP file input. A successful
  import atomically replaces the workspace; a failed import preserves the
  current workspace and editor state.
- A session-owned `metadata_loaded` flag distinguishes an untouched empty
  session from a successfully imported bundle. It is set only after successful
  import and is not inferred from collection lengths, because an imported
  bundle may legitimately contain empty collections.
- Before the first successful import, the main body shows an upload-required
  welcome state. Metadata-dependent dashboards show an empty-state prompt,
  while `Download metadata` is disabled. `Upload metadata` and `Download demo
  package` remain available.
- Re-importing while an editor is dirty first uses the existing Discard/Cancel
  guard and then requires workspace replacement confirmation. A clean
  re-import requires replacement confirmation only.
- `Download metadata` exports the last saved workspace snapshot and never
  commits an active draft. `Download demo package` is independent of workspace
  and draft state and returns a ZIP containing the synthetic demo metadata ZIP
  and the user guide.
- Template chunks are rendered as independent cards.
- Compact chunk fields use a responsive three-column grid. Long SAS expressions
  and rows/statistics DT editors retain wider or full-row layouts. Chunk move
  and delete actions are placed at the far right of each card header; internal
  session-local UI identities are not displayed.
- `test/fixtures/demo_metadata.zip` is a synthetic bundle covering FAS/SAFETY,
  baseline AGE/SEX analyses, and a SOC/PT AE severity hierarchy.
- Header columns and spanning headers are edited in one DT. Spanning fields are
  displayed as labels; on save, contiguous label runs are converted to
  canonical `spanning_headers` IDs and column references. Existing column IDs
  remain read-only, while display order and width are converted to integer and
  numeric values respectively.
