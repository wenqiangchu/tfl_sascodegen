# Tests

Run the full automated suite from the repository root:

```text
Rscript test/run_tests.R
```

Tests cover the approved metadata, workspace, source-generation, and Shiny
boundaries. Fixtures are synthetic and contain no analysis datasets.

| Coverage | Test files |
| --- | --- |
| YAML/ZIP round trips, saved drafts, import failures | `test-yaml-codec.R`, `test-workspace.R` |
| Import, edit, save, export, reimport, identical Report/QC source | `test-application.R` |
| Initial upload gate, clean/dirty Header navigation | `test-shinytest2-upload-gate.R`, `test-shinytest2-header-navigation.R`, `test-ui-header-editor.R` |
| Editor actions, source preview, Report/QC selection, download availability | `test-shinytest2.R` |
| SAS filename and exact source file writing | `test-ui-generation-download.R` |
| Generation contracts, report layout, primitive and hierarchical source | `test-source-generator.R`, `test-report-source.R`, `test-z-*.R`, FDA source/fixture tests |

Browser tests require Chrome and are not silently skipped. They assert DOM and
application state, not screenshot appearance. Browser download availability
and source-file writing are tested separately; there is no automated assertion
that a browser-saved download matches the preview byte for byte.

`fixtures/sas/continuous_counting_units/` contains a SAS 9.4 runtime fixture
for hierarchical continuous `record`, `distinct_subject`, and `distinct_key`
semantics. The tracked SAS files only create synthetic `WORK` datasets and
assert results. Generated table programs, logs, and RTF files remain ignored.

`fixtures/sas/hierarchical_continuous_batching/` compares shared MEANS with
independent block execution, including precision, all eight raw statistics,
logical cells, empty inputs/columns, and second-block counting-unit conflicts.

`fixtures/sas/hierarchical_row_assembly/` provides hand-calculated expected
wide rows for multiple nodes, result sorting, multiple levels, same-row/below
placement, label rows, categorical children, mixed chunks, and empty input.
Its external SAS assertions compare all row identities and cells, including
final assembly and spacer positions; paired equivalence is not the oracle.
The R suite checks generated source only and does not execute SAS.

External SAS results in the documentation predate the removal of generated
CARDIMAGE management. They are historical runtime evidence, not a fresh SAS
validation of the final source. See `docs/source-generation-closeout.md` for
the current test run and the separately reported user end-to-end test.
