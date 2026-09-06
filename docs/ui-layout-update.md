# UI layout update

The Shiny dashboard now follows the approved metadata editing layout:

- Metadata is split into Population and Header tab panels.
- Each metadata area uses a left object list and a right detail editor.
- Selecting a ZIP automatically imports it when the workspace is empty; when
  metadata is already loaded, a confirmation dialog is shown before replacement.
- Template chunks are rendered as independent cards.
- `test/fixtures/demo_metadata.zip` is a synthetic bundle covering FAS/SAFETY,
  baseline AGE/SEX analyses, and a SOC/PT AE severity hierarchy.
- Header columns and spanning headers are edited in one DT. Spanning fields are
  displayed as labels; on save, contiguous label runs are converted to
  canonical `spanning_headers` IDs and column references. Existing column IDs
  remain read-only, while display order and width are converted to integer and
  numeric values respectively.
