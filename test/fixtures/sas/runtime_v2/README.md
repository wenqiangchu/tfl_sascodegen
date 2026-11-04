# External SAS 9.4 validation

These scripts are developer tools, separate from Shiny and `test/run_tests.R`.
They execute SAS and inspect data only when invoked explicitly. Inputs in
`study/` are local and are never copied into Git fixtures.

Requirements: R with the project's packages; Python with pandas, numpy, Pillow,
pypdf and pywin32; local SAS; Microsoft Word; `pdftoppm` on PATH. The SAS runner
uses `TFL_SAS_EXECUTABLE`, defaulting to `E:\sas\SASFoundation\9.4\sas.exe`.
SAS and rendering workers have timeouts; SAS processes use hidden windows.
Word runs invisible and closes documents without saving.

Run from the repository root. Choose a **new batch name** for each execution;
completed run directories are immutable. Each SAS case has its own process,
working directory, output paths and transient WORK library. Study libraries
are bound `ACCESS=READONLY`. Original input hashes are checked after study runs.

```powershell
$batch = 'rerun_20261102_01'
$fixture = 'test/fixtures/sas/runtime_v2'
Rscript "$fixture/study/build_study.R"
Rscript "$fixture/build_sources.R"
Rscript "$fixture/build_denominators.R"
Rscript "$fixture/build_severity.R"
python "$fixture/study/run_study.py" --batch $batch
python "$fixture/study/independent_study.py" --batch $batch
python "$fixture/study/compare_study.py" --batch $batch
python "$fixture/run_formats.py" --batch $batch
python "$fixture/run_denominators.py" --batch $batch
python "$fixture/run_denominators.py" --batch $batch --fixture severity_case
python "$fixture/run_header_warning.py" --batch $batch
python "$fixture/run_existing.py" --batch $batch
python "$fixture/run_qc.py" --batch $batch --report-batch $batch
python "$fixture/verify_lengths_severity.py" --batch $batch
python "$fixture/run_performance.py" --batch $batch
python "$fixture/study/render_originals.py"
python "$fixture/study/render_rtf.py" --batch $batch
python "$fixture/study/compare_rtf.py" --batch $batch --baseline-batch $batch
python "$fixture/audit_logs.py" --batch $batch --qc-batch $batch --order-batch $batch --empty-batch $batch
python "$fixture/build_completion_audit.py" --batch $batch --study-batch $batch --qc-batch $batch
Rscript test/run_tests.R
```

`build_completion_audit.py` recomputes `study/validation_v2/completion_audit.json`
from the artifacts above; every entry records the file it was read from, so rerun
the generator after a rerun instead of editing the audit by hand. It separates
analysis failures (`failed_checks`, nonzero exit) from Word pagination items
(`presentation_failures`), which are reported but never counted as passes.

The corpora may also be split across batches. `run_qc.py` needs its reference
tables from the study batch, and `verify_lengths_severity.py` needs the format
fixture's column inventory in its own batch, so a split run looks like:

```powershell
python "$fixture/study/run_study.py" --batch $study --mode both
python "$fixture/run_formats.py" --batch $fixtureBatch
python "$fixture/run_qc.py" --batch $qc --report-batch $study
python "$fixture/audit_logs.py" --batch $fixtureBatch --study-batch $study --qc-batch $qc --order-batch $fixtureBatch --empty-batch $fixtureBatch
python "$fixture/build_completion_audit.py" --batch $fixtureBatch --study-batch $study --qc-batch $qc
```

Check every command's exit code. Also inspect the JSON assertions, `comparison`
and RTF reports: a successfully completed comparison can report differences.
In particular, RTF rendering completion does not imply presentation acceptance.
The current Word rendering has a documented trailing blank page for 14.1.1.
`compare_rtf.py` keeps that failed assertion visible.

The initial migration is explicit and limited to the three known v1 bundles.
`study/build_study.R` records each denominator, counting-unit and retired-field
change, uses the canonical v2 serializer, and checks import/export byte identity
and repeatable Report/QC source generation. Both versions of 14.1.2 are retained.
It deliberately fails on unexpected legacy shapes instead of guessing.

Literal synthetic expectations live in `format_cases.R`, `denominator_case.R`
and `build_severity.R`. The independent study oracle uses pandas source-data
grouping, including the historical PT-only maximum severity preparation.
Counts and displayed strings are exact; floating raw statistics allow absolute
error `1e-12`, with no relative tolerance. Reference display rounding removes
floating noise at 12 decimal places before decimal half-up rounding, consistent
with SAS ROUND at the tested precision. Actual output strings are never rounded
or normalized by the checker.

`run_existing.py --verify-only` reaudits retained old-fixture logs. Intentional
negative digits and conflict diagnostics have exact counts. `audit_logs.py`
records every warning/error and significant conversion/uninitialized note;
unexpected categories fail. SASHELP installation warnings and SASUSER registry
copy warnings are recorded separately from analysis diagnostics.

Performance runs snapshot `cd716d0` and the current source into isolated build
contexts. Each size has three alternating-version trials with identical inputs
and exact result equivalence. The timer covers analysis through assembly, not
startup, fixture creation, RTF rendering or snapshot persistence. WORK size is
the sum of final `_TFL_*` dataset file sizes, **not peak disk or memory**.

Evidence for the 2026-11-02 run is indexed in
`study/validation_v2/validation_report.md`. Generated metadata, SAS, data, logs,
RTF, PDF, images and machine state remain under ignored `study/validation_v2/`.
