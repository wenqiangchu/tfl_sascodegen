# SAS Descriptive-Analysis Code Generator

This repository is being initialized from the portable metadata contract in
`table-and-chunk-analysis-model.md`. The first implementation target is a
Shiny application that edits an in-memory metadata workspace and emits SAS
source text; it does not execute SAS or manage analysis datasets.

The design contract is recorded in `docs/design-decisions.md`; implementation
follows the acyclic stages in `plans/implementation-plan.md`.
