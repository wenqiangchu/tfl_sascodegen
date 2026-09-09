# SAS Descriptive-Analysis Code Generator

This repository is being initialized from the portable metadata contract in
`table-and-chunk-analysis-model.md`. The first implementation target is a
Shiny application that edits an in-memory metadata workspace and emits SAS
source text; it does not execute SAS or manage analysis datasets.

The design contract is recorded in `docs/design-decisions.md`; implementation
follows the acyclic stages in `plans/implementation-plan.md`.

## Run the application

On Windows, double-click `start_app.bat`. The launcher binds to loopback and
selects the first available port in the `3838`-`3938` range, then opens the
application in Chrome. Alternatively run:

```r
shiny::runApp('.', host = '127.0.0.1', port = 3838)
```

The application emits SAS source text only. Dataset references and SAS
expressions in metadata are preserved as user-provided source and are not
executed or validated by the application.

## Run tests

From the repository root:

```text
Rscript test/run_tests.R
```

The suite includes metadata YAML/ZIP round trips, source-generation section
ordering and snapshots, emitter regressions, workspace draft behavior, and
Shiny interaction coverage through `shinytest2`. Browser tests require a
working Chrome installation discoverable by `shinytest2`/Chromote.
