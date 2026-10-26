# Implementation plans

The confirmed stage division and implementation plan are recorded in
`implementation-plan.md`. Production work must follow its dependency DAG and
phase gates.

Follow-up plans that supersede or extend part of the baseline:

- `counting-unit-unification.md` — unify `counting_unit` across all analysis
  chunks, remove `source_contract`, and move duplicate checking to the same
  layer and key as deduplication. Supersedes the reverted automatic
  deduplication feature (commits `89212a3` and `b602244`).
