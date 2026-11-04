# SAS runtime validation work item

External development validation starts at `ea4e228`. SAS execution and study
data access remain outside Shiny and the ordinary R test suite.

| Requirement | Evidence | Status |
| --- | --- | --- |
| Isolation and preservation | Per-case execution records; 32 original-input hash checks | Passed |
| Three v2 bundles / seven configurations | Explicit migration, canonical round trips, deterministic Report/QC source | Passed |
| Historical analysis regression | Header N, numerator/denominator, statistics, nodes and logical cells | All seven passed |
| Independent hierarchy oracle | Source-data grouping, complete rows, order, indentation, spacers and cells | 13,440 assertions passed |
| Format boundaries | 13 cases, empty roots with all missing policies, UTF-8 labels, child order | Passed |
| Denominators / SOC-PT / lengths | 159 denominator, 123 severity and 20 descriptor/presentation assertions | Passed |
| Header uniqueness warning | Before-population check, checked/unchecked paths, records preserved | Passed |
| Existing SAS fixtures | Five counting-unit, ten batching, five assembly cases regenerated | All 20 passed |
| QC sensitivity | Seven equal and seven deliberately changed results | SYSINFO 0 / 4096 |
| RTF regression | Original/baseline pixels equal; exact current cells, headers, indentation and widths | Passed except pagination item below |
| Length optimization | Two sizes, three trials per version, equal results, actual widths and final WORK bytes | Passed with measurement limits |
| Final source verification | Full R/Shiny suite, focused regressions, diff check | Passed |

The sole unresolved presentation item is a trailing blank page when Word
16.0.19127 renders `ref_141__14.1.1`. All content is on page 1. The failed
page-header assertion remains visible; no page or whitespace was removed.
A diagnostic RTF copy with a one-point final paragraph renders on one page.
Inline ODS TEXT probes did not solve it. A broader generated report-style
decision is pending; it is not an analysis correctness failure.

Production changes:

- Seed the formatted root catalog even when input is completely empty.
- Preserve MEANS format order across the parent SQL join.
- Keep unformatted sibling counters local to their discovery step.
- Reserve the outer RTF border width to prevent horizontal panel splitting.
- Add the user-approved Header uniqueness warning and tighten documentation.

The historical final-assembly `row_sequence` defect was fixed at the starting
commit; this work independently proves the corrected output. Historical PT-only
severity preparation stays intact; SOC/PT-specific maxima use a separate case.

Reusable commands: `test/fixtures/sas/runtime_v2/README.md`.
Detailed local report: `study/validation_v2/validation_report.md`.
Input/source hashes: `study/validation_v2/evidence_manifest.json`.
Authoritative runs: `runs/final`, `runs/qc_verified`, `runs/unformatted_verified`,
`runs/empty_policies`. Baselines: `runs/initial`. Failed attempts remain retained
and classified. Study artifacts and machine state remain ignored.

Preserve unrelated `ref/` and `ui-and-backend-design.md`. No product execution or
data inspection, record-selection field, tree hierarchy, format existence/type
checks, ranges, OTHER, special-missing or multilabel support was introduced.

## 2026-11-03 PI review fixes and ignored-study tracking

The ignored `study/` tree contains development-only SAS inputs, generated source,
logs, RTF/PDF files, and validation evidence. Because `.gitignore` contains
`study/`, ordinary `git diff` does not show edits there; `study/` has no nested Git
repository and currently contains zero Git-tracked files. The before/after snapshot
under `tmp/study-validation-review-2026-11-03/` covers only five files, not every
overwritten run result. Both `tmp/` and `study/` are ignored, so these snapshots are
temporary evidence and will not survive cleanup unless copied elsewhere. The
reusable validation scripts live under tracked `test/fixtures/sas/runtime_v2/`,
where their code changes are visible in ordinary Git diffs. Study-specific SAS
outputs and reports remain local and uncommitted.

This review corrected the report's evidence wording (29 before/after hashes plus
three ZIP boolean-only checks, the numeric `VVALUE` coverage boundary, oracle scope,
performance metric scope, audit keyword scope, expected negative errors, and
superseded run directories). It also excludes `_TFL_HSUBJ%` diagnostic tables from
the benchmark's final intermediate-byte total so Header duplicate diagnostics do not
change the measurement definition; the benchmark was rerun and its result is in the
local validation report. The tracked study comparison now rejects missing required
fields, compares cells by paragraph, checks stub width, uses each case's actual
Header N, and exits nonzero on a failed case. The current rerun has six RTF cases
passing and the documented blank second page in `ref_141__14.1.1` still failing.
Numeric `VVALUE` ordering was restored as a synthetic case and rerun. No analysis
semantics or Shiny boundary changed during these review fixes.

The temporary SHA-256 ledger records five paths: `compare_study.py`,
`compare_rtf.py`, `validation_report.md`, and the `unformatted_order` SAS program
and expected JSON. Four hashes changed; the expected JSON did not. The ledger and
before/after copies remain under ignored `tmp/`; they are useful for this active
review but are not durable repository history. Do not infer from Git status that
the study outputs were unchanged.

## 2026-11-03 Fix round: blocker, harness consolidation, restated evidence

A follow-up code review of the review fixes found one blocker and one partial fix, both
introduced by the earlier round:

1. The shared catalog sort emits `by parent_node_key _tfl_format_order;` for every
   formatted level, but only levels ≥ 2 assigned `_tfl_format_order`. A formatted
   root therefore failed at compile time with `变量 _TFL_FORMAT_ORDER 没有找到`
   (returncode 2, cascading nonexistent-dataset errors). Level 1 now records
   `_tfl_format_order = _n_` as well. This was proven by executing a pre-fix
   generated program in a scratch directory, not by inspection.
2. `strip(vvalue(...))` was applied to the catalog and unformatted paths but not to
   the formatted `observed` step, so node labels and analysis-row labels could
   disagree. The formatted side now strips identically.

Re-running the study configurations exposed a third, previously unexercised defect:
the Header duplicate diagnostic passed a function call directly to `PUTLOG`, which
is invalid SAS (PUT takes variables and formats, not expressions). Every generated
program with `include_duplicate_check` enabled failed with `ERROR 22-322: 期望:
arrayname`. It had never run because the synthetic format suite generates with
`include_duplicate_check = FALSE`. The count is now materialized into
`_tfl_count_text` before `PUTLOG`.

Two permanent guards were added. An R test asserts that every internal `_tfl_*`
sort key is assigned in the same level that sorts by it (verified to fail when the
level-1 assignment is removed), and another asserts both label paths strip padding
(verified to fail when the assignment is reverted). `run_formats.py` additionally
reports `sort_key_defined` by matching sort keys against `ERROR` lines, which is
locale-independent.

The harness had also forked: `study/validation_v2/*.py` and
`test/fixtures/sas/runtime_v2/study/*.py` were both being edited, and they diverged
in both directions (`compare_rtf.py` newer in the tracked copy, `render_rtf.py`
newer in the ignored copy). The ignored copy is what actually ran, so verifying the
tracked copy proved nothing about the evidence. The tracked scripts are now the
single implementation, and the ignored duplicates are deleted; a test fails if a
copy is reintroduced under `study/validation_v2/`. Tracked scripts resolve the
repository root themselves at `parents[5]`, so they run in place.

Study comparison additionally treats statistic columns as optional per chunk type:
`_n`, `_mean`, `_sd`, `_median`, `_q1`, `_q3`, `_min`, `_max`, `analysis_id`,
`numerator` and `denominator` are absent from both sides for categorical-only
tables. Symmetric absence is recorded as `absent_from_both` and is not compared;
asymmetric absence still fails.

### Evidence now aligned to the reviewed source

| Corpus | Batch | Result |
| --- | --- | --- |
| 13 format/ordering cases | `runs/format_fixed_20261103/` | 13/13 process and assertions |
| Seven historical configs | `runs/study_fixed_20261103/` | 14 processes, 0 ERROR; 7/7 analysis and logical cells equal |
| Independent hierarchy oracle | `runs/study_fixed_20261103/` | 13,440 assertions, 0 failed |
| QC seven cases equal/changed | `runs/qc_fixed_20261103/` | 14/14, SYSINFO 0 / 4096 |

`compare_study.py` still exits 1 for this batch: the three hierarchical cases
reproduce the known historical defect (`row_sequence`/inherited sibling counter),
so `historical_order_equal` and `assembly.passed` are false while the independent
oracle passes and supplies the classification. That is the pre-existing, disclosed
state, not a new regression.

Still produced by the pre-fix source and therefore not covered by the table above:
RTF rendering/comparison, denominators, severity and length assertions, existing
fixtures, and the length/performance comparison. `evidence_manifest.json` records
this per corpus under `code_version.evidence_versions`. The current run's RTFs have
not been rendered or compared, so the report's page counts remain from the earlier
batch.

### Evidence consolidation and generated completion audit

The remaining corpora were rerun onto the reviewed source so that no evidence
predates the fixes. Fixture-based corpora now live in one batch
(`aligned_20261103`): 13 format cases, 159 denominator and 123 SOC/PT assertions,
20 length/display assertions, the Header duplicate diagnostic, the three legacy
fixture groups (20 cases), the length/performance comparison, and the log audit
(70 runs, no unclassified entries). Study configurations and the independent
oracle stay in `study_fixed_20261103`, and QC in `qc_fixed_20261103`, because
`run_qc.py` reads its reference tables from the report batch and
`verify_lengths_severity.py` reads the format fixture's column inventory from its
own batch. `audit_logs.py` gained `--study-batch` so it can span those batches.

RTF was re-rendered and re-compared for the study batch: six cases pass and
`ref_141__14.1.1` still renders a blank second page, so the comparison exits 1.
Page counts are unchanged from the earlier batch (1/1, 1/1, 1/24, 1/12, 1/37,
2/2, 6/3), and the per-case Header N is now read from each case instead of a
hard-coded value. Rendering reuses a cached layout only when the recorded
`source_sha256` still matches the RTF, and stale `layout.json`, PDF and page
images are deleted before a re-render so a longer earlier render cannot leave
extra page images behind.

`completion_audit.json` is no longer hand-authored:
`test/fixtures/sas/runtime_v2/build_completion_audit.py` recomputes all 43 checks
from the retained artifacts, records the file behind each check, and separates
analysis failures from Word pagination items. The performance medians in the
report were updated to this run (120 rows: 1.133 / 0.623 s; 600 rows: 2.229 /
0.743 s); final WORK bytes are deterministic and identical across both runs.
