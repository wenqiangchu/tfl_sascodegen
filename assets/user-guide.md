# SAS Code Generator user guide

This application imports a metadata ZIP bundle, edits saved metadata in the
current browser session, and generates descriptive-analysis SAS source text.

The included `demo_metadata.zip` contains synthetic metadata that can be used
to explore the application. Upload it with `Upload metadata`, select metadata
objects in the dashboard lists, save intended edits explicitly, and use the
Generate SAS dashboard to preview or download source for a selected table.

The application does not read or execute SAS datasets. Dataset references and
SAS expressions are emitted as entered and remain the user's responsibility.

## Start

On Windows, double-click `start_app.bat`; it selects an available local port
and opens Chrome. Alternatively run `shiny::runApp('.')` from the project
directory. Upload a bundle with `Upload metadata`. The demo package contains a
synthetic bundle and this guide.

## RTF source generation

The following report conventions apply to **Source report (PROC REPORT)** mode.
QC mode generates `PROC COMPARE` after table assembly and custom code instead.

Each Header requires `orientation: portrait` or `orientation: landscape`.
Select **Page orientation** in the Header editor before saving a new Header.
The demo explicitly uses portrait for the FAS header and landscape for the
safety header. Earlier bundles must add this field; import does not infer it.

The generated program targets SAS 9.4. After saving the `.sas` program in the
clinical project, run it with the SAS current working directory set to the
program directory. `ODS RTF` writes `<table_id>.rtf` there and replaces an
existing file of that name. The application generates source only; run and
inspect the program and the RTF in your own SAS environment.

Programs use Letter paper and the built-in `Styles.Rtf` style (`style=rtf`).
Left and right margins are explicitly one inch, giving 6.5 inches in portrait
or 9 inches in landscape. The stub width is that usable width minus the sum
of the Header column widths. Fonts and borders follow the RTF style. Column
labels and spanning headers follow the metadata; each column also shows
`(N = xx)` from its population/header membership, including `(N = 0)`.

The generated order is custom code **before**, population/header derivation,
analysis and table assembly, custom code **after**, and finally `PROC REPORT`
and `ODS RTF CLOSE`. The demo includes both custom-code fields. The report
always reads `WORK._TFL_ASM_001`; edits in **after** must write back to that
dataset and retain these fields:

| Field | Use |
| --- | --- |
| `report_order` | Numeric report-row order; keep it unique per physical row. |
| `label` | Character stub text, including user-supplied RTF. |
| `indent_level` | Numeric indentation depth; each level contributes `\li200`. |
| `col_001`, `col_002`, ... | Character cells in Header display order. |

The assembly also retains `chunk_order`, `row_sequence`, `chunk_id`, `row_id`,
`runtime_row_id`, `row_role`, `hierarchy_level`, and `node_key` for identifying
rows in custom code. Runtime identities and all report datasets remain in
SAS WORK and are not metadata fields.

Label rows use normal font weight. One blank row separates chunks and changes
between hierarchical levels; coincident boundaries produce one blank row.
Consecutive rows at the same level do not receive extra gaps. ODS RTF repeats
column headers across pages. No titles, footnotes, automatic label wrapping,
or keep-with-next rules are generated. User-supplied label RTF is preserved.

## Bundle layout

A bundle contains `manifest.yaml`, `populations.yaml`, `headers.yaml`, and
independent `tables/<table-id>.yaml` and `templates/<template-id>.yaml` files.
The manifest currently declares the schema version.

## Editing workflow

- Select an object in the left list to show its detail panel.
- Use `New`, enter the requested top-level ID, and edit the draft.
- Click the relevant `Save` button to commit changes.
- `Discard changes` restores the last saved version; for a new object it
  removes the unsaved object.
- Switching with unsaved changes offers `Discard changes` or `Cancel`.
- Existing-object deletion is immediate after required confirmation/reference
  checks.

## Templates

Templates contain independent chunk cards. Rows and statistics use one shared
DT; one DT row corresponds to one RTF row. Statistics and digits are
space-separated, for example `n mean sd` and `0 1 1`. Hierarchical chunks
contain nested levels and analysis blocks with parent relationships and
structured denominators.

## Header and population

Header columns and spanning headers are edited together in one DT. Spanning
labels are converted to canonical contiguous spans when saved. Conditions,
filters, source data, and custom code remain opaque SAS source text.

## Generate and download

In `Generate SAS`, select a table, choose the generation options, and click
`Generate SAS`:

- **Include duplicate record checks** is enabled by default. Clear it to omit
  the source-key duplicate checks and their `WARNING: [USER] duplicate_key`
  messages. This applies to primitive chunks and hierarchical source records;
  it does not change analysis counts, merge rules, or exclusive-category
  overlap warnings.
- **Remove duplicate source records before analysis** is disabled by default.
  When enabled, the generated program sorts each filtered source by the same
  keys the duplicate check uses and keeps only the **first** record per key
  (`PROC SORT ... NODUPKEY`). Later records are dropped before merge, counting,
  denominators, and hierarchical node discovery, so counts change and the
  duplicate check no longer reports the removed records. The retained record is
  the first one in input order, so source ordering determines the result.
  This option is independent of the duplicate check; enabling both removes
  duplicates first and then checks the surviving records.
- **Source report (PROC REPORT)** is the default output mode. It appends the
  report and ODS RTF statements described above.
- **QC compare (PROC COMPARE)** appends
  `proc compare base=tables.<table_id> compare=WORK._TFL_ASM_001 listvar;`.
  Prepare the source-side dataset and bind the `TABLES` library in your SAS
  environment. It must have the intended matching variables and observation
  order; the generator does not create or reorder the source-side dataset.
  A table ID such as `14.1.2` becomes `tables.'14.1.2'n` with
  `VALIDMEMNAME=EXTEND`. QC mode emits no system-generated ODS RTF or PROC REPORT
  statements, and RTF page-width constraints do not block it.

Both modes run the same analysis and assembly source, then preserve
`custom_code.after` before the selected final procedure. User custom code is
always emitted unchanged. These options belong to the current UI session and
generation request; they are not metadata fields and are not exported in the
bundle. Changing a table or an option hides the old preview and disables SAS
download until a new successful generation.

Header membership uses one DATA step with an independent `IF ... THEN DO` and
`OUTPUT` for each column. A subject can therefore belong to both a treatment
column and an overall column. `_TFL_KEY_MAP_*` uses `INPUT` and delimited
`DATALINES` (`DATALINES4` when the data contains semicolons), with quoted text
fields and explicit character informats. Each chunk/row/statistic is listed once;
`CROSS JOIN` with the shared `_TFL_HCOLS_001` header catalog expands the column
dimension into `_TFL_KEY_*`. Declared columns with no population members are
retained. Hierarchical analyses also cross join their scoped node catalog.

INPUT fields are listed on separate lines. Short Header and counting rules use
one line per rule, while nested calculations and error handling remain expanded.
The generator does not save, change, or restore CARDIMAGE; inline record reading
uses the caller's SAS session settings.

The application generates source only; it does not read, validate, or execute
SAS datasets.
`Download metadata` exports the last saved workspace snapshot and never
implicitly saves active edits. `Download demo package` is independent of the
current workspace.

## Tests

Run `Rscript test/run_tests.R` from the project directory. The suite covers
YAML/ZIP round trips, source-generation regressions, and shinytest2 interaction
tests.
