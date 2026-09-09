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

In `Generate SAS`, select a table and click `Generate SAS`. The application
generates source only; it does not read, validate, or execute SAS datasets.
`Download metadata` exports the last saved workspace snapshot and never
implicitly saves active edits. `Download demo package` is independent of the
current workspace.

## Tests

Run `Rscript test/run_tests.R` from the project directory. The suite covers
YAML/ZIP round trips, source-generation regressions, and shinytest2 interaction
tests.
