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
of the Header column widths, the two outer borders at 0.75 point each, and a
0.25 inch fit reserve. The outer border width is fixed at 0.75 point; the fit
reserve exists because cell padding and borders are not part of the declared
column widths, and classic ODS RTF splits the table into horizontally repeated
panels when the grid has no slack. Fonts otherwise follow the RTF style. Column
labels and spanning headers follow the metadata; each column also shows
`(N = xx)` from its population/header membership, including `(N = 0)`.

The generated order is custom code **before**, population/header derivation,
analysis and table assembly, custom code **after**, page pagination, and
finally `PROC REPORT` and `ODS RTF CLOSE`. The demo includes both custom-code
fields. Your **after** code must update `WORK._TFL_ASM_001` in place and retain
these fields:

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

Pagination runs **after** your **after** code, so its edits are carried into the
pages. It re-sorts `WORK._TFL_ASM_001` by `report_order` before assigning rows to
blocks, so **after** code may append or insert rows without keeping physical order
consistent with `report_order` -- use `proc append ... force` if needed. It reads
`WORK._TFL_ASM_001` and writes `WORK._TFL_PAGED_001`, which is what `PROC REPORT`
renders; `_TFL_PAGED_001` adds `page_group` (the page number) and
`_tfl_print_order` (the row's printing position in the whole table, which is what
the report orders by -- it is the row number after the final sort, so it keeps
counting across page boundaries instead of restarting on each page). That means the
report does not read `_TFL_ASM_001` directly. All other pagination bookkeeping is
dropped from that dataset. Compare mode skips pagination and diffs
`WORK._TFL_ASM_001` against the saved table, so the QC path is
unaffected by page layout.

Label rows use normal font weight. One blank row marks a **block boundary**: a
new chunk, a top-level node, or a node following the below rows it owns.
Coincident boundaries produce one blank row. Consecutive nodes at the same depth
receive no gap, because indentation already expresses the nesting; a node with
below rows does, because those rows share the indent of the next sibling.
ODS RTF repeats column headers across pages.

Pages are paginated by the Header's `page_rows`, edited as **Page capacity** on
the Header tab (default 22 printed lines, `0` disables breaking, otherwise the
minimum is 4). The value is always saved in the bundle, including when it equals
the default, so a bundle states its own layout instead of inheriting whatever the
current default happens to be. Every page opens and closes with one blank line, so at most
`page_rows - 2` body lines are used, and repeated column headers do not count
toward it. A block is never split across pages, with one exception: a block
taller than a whole page cannot fit anywhere, so it fills the page and continues.
Each page carries a right-aligned roman 10pt `Page x of Y` footer. No titles,
automatic label wrapping, or keep-with-next rules are generated. User-supplied
label RTF is preserved.

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

## Counting units

Every analysis chunk and every hierarchical analysis block declares a
`counting_unit`. It decides what one counted observation is, and it is
required, so an imported bundle without it is rejected.

| `counting_unit` | One unit is | Duplicate check | Deduplication |
| --- | --- | --- | --- |
| `record` | One source record | None | None |
| `distinct_subject` | One `USUBJID` | On `USUBJID` | Collapses repeated subjects |
| `distinct_key` | One combination of the declared `distinct_key` fields | On `distinct_key` | Collapses repeated keys |

`record` counts every record as its own unit, so its key is the source row
number, which is unique by construction. A duplicate check there could never
report anything, so none is generated and nothing is deduplicated. Use
`record` for observation-level statistics and `distinct_subject` when each
subject must contribute once.

`distinct_key` requires a `distinct_key` field listing the key variables in
order, for example `USUBJID, AVISITN`. Leave that field empty for the other
two units; a non-empty key with a different unit is rejected.

The duplicate check is on by default and reports each duplicated key at most
once. It never drops records; it only writes `WARNING: [USER] duplicate_key`
to the SAS log. Turning it off in the generate step removes only the check.

### Continuous statistics and multiple values

`distinct_subject` and `distinct_key` continuous chunks reduce each unit to one
value before `PROC MEANS` runs, so `n` counts units rather than records. When a
unit contributes more than one non-missing value, the generator cannot pick one
without inventing a rule, so it writes
`WARNING: [USER] continuous_unit_multiple_values` to the SAS log and keeps the
value from the first non-missing record in input order - the smallest
`source_row`. The run continues.

This means the result depends on input row order, which a preceding sort fully
determines. The warning is a data-quality signal, not a fatal error: check the
log and make the source unique per unit if that is what the analysis requires.

### Migrating an older bundle

Bundles exported before counting units existed have no `counting_unit` field
and no longer import. Add `counting_unit: distinct_subject` to each analysis
chunk and each hierarchical analysis block, which reproduces the previous
subject-level behaviour. The removed `source_contract` block should be
deleted rather than translated: its subject key is now fixed to `USUBJID`
and its duplicate policy had only one accepted value.

## Header and population

Header columns and spanning headers are edited together in one DT. Spanning
labels are converted to canonical contiguous spans when saved. Conditions,
filters, source data, and custom code remain opaque SAS source text.

## Generate and download

In `Generate SAS`, select a table, choose the generation options, and click
`Generate SAS`:

- **Include duplicate record checks** is enabled by default. Clear it to omit
  the source-key duplicate checks and their `WARNING: [USER] duplicate_key`
  messages, and the Header source `WARNING: [USER] header_subject_duplicate`
  check. Header source must contain one record per `USUBJID`; prepare it before
  running the program. Warnings do not remove duplicate records or stop SAS.
  This option applies to primitive chunks and hierarchical source records;
  it does not change analysis counts, merge rules, or exclusive-category
  overlap warnings.
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

## Field reference

This section lists the limits the application actually enforces. They come from
real downstream boundaries -- the SAS format width, the SAS character variable
length, the SAS member name length, and file names in the bundle archive -- not
from a preference for tidy values. When a value falls outside its range the
import is refused with an error that names the field and the rule, rather than
being adjusted silently.

### Identifiers

| Field | Allowed | Why |
| --- | --- | --- |
| `tables[].id`, `templates[].id` | letters, digits, `_`, `.`, `-`; at most 32 bytes; non-empty | These become physical names: the archive entries `tables/<id>.yaml` and `templates/<id>.yaml`, the report file `<id>.rtf`, and the SAS member `tables.<id>`. A `/` in the id produces a bundle that exports but cannot be imported again, and more than 32 bytes exceeds the SAS member name limit. |
| Every other id (population, header, column, spanning header, chunk, level, block, row, statistic) | non-empty | These are references or in-memory keys. Chunk ids are renumbered when the bundle is saved and written as SAS character literals; column ids become `col_NNN` and never reach SAS. Restricting them would reject bundles that work today. |

### Numbers and text

| Field | Allowed | Why |
| --- | --- | --- |
| `statistics[].digits`, absolute | `0` to `31` | The generator emits `PUTN(value, cats('F', 32, '.', digits))`. SAS requires `0 <= d <= 31` and `d < w`, and `w` is fixed at 32. |
| `statistics[].digits`, relative (`+n` / `-n`) | offset `-31` to `+31` | The resolved value is `base_digits + offset`, where `base_digits` comes from the data at run time, so only the offset can be checked on the host. |
| `indent_level` | `0` to `9` | Indentation is `indent_level * 200` twips. A larger value pushes the stub off the page. |
| Any metadata text | at most 32767 bytes | 32767 is the largest SAS character value. Longer text cannot be represented in the generated program. |
| `page_rows` | `0`, or `4` to `2147483647` | `0` disables pagination. `1` to `3` cannot hold a header row plus the forced blank lines at both page edges. |

If the digits a chunk resolves to at run time exceed 31, the generated program
writes `ERROR: [USER] ...` to the log, marks that statistic as not estimable, and
shows `NE` in the cell. It does not abort the run.

### Optional SAS expressions

`filter`, `denominator.expression` and `rows[].condition` are SAS expressions. The
application preserves them exactly as written, including surrounding spaces, and
never evaluates them. A value that is only whitespace is treated as "not
provided" in all three, so a placeholder left in an editing form is not an error.

### Cross-references checked on import

| Rule | Reason |
| --- | --- |
| `tables[].population_id`, `header_id`, `template_id` must exist | A missing reference leaves the table incomplete. |
| `levels[].node_analysis_id` must name a `same_row` block anchored at that level | The block renders on the level's own node row. |
| Every `same_row` block must be referenced by some level's `node_analysis_id` | An unreferenced block is still analysed and emitted, but never displayed. |
| A `same_row` block may hold exactly one row | All rows of the block share one output row, so only the last would be rendered. Use `below` for several rows. |
| `result_sort.metric.analysis_id` must name a block anchored at the level being sorted | Otherwise the sort key never matches the nodes and the ordering silently falls back to declaration order. |
| `column_order` positions must not exceed the header's column count | A position past the last column addresses nothing. `0` is not a position: it means "after the numbered columns". |

The `column_order` limit is checked when source is generated, against the header
the table actually resolves to, because a template can be attached to a header
with fewer columns after import. The others are checked when the bundle is
imported.

## Tests

Run `Rscript test/run_tests.R` from the project directory. The suite covers
YAML/ZIP round trips, source-generation regressions, and shinytest2 interaction
tests.
