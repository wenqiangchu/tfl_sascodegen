# Hierarchical final row assembly fixture

The R builder generates SAS source and hand-calculated expected rows. It does
not run SAS or read study data. `prepare_data.sas` creates two synthetic
subjects and four WORK records; child labels X/Y repeat under parents A/B.

| Case | Long cells | Wide rows | Final rows including spacers | Coverage |
| --- | ---: | ---: | ---: | --- |
| basic | 12 | 4 | 4 | Two nodes, same-row and below blocks with the same local row ID; three Header columns. |
| sorted | 12 | 4 | 4 | Second-block raw mean sorts B before A without changing logical identities. |
| multilevel | 30 | 10 | 13 | Parent label, below label/mean, categorical same-row children, repeated child labels, sorted parent paths. |
| mixed | 27 | 9 | 11 | Two containers separated by an ordinary continuous chunk; row counters restart per chunk. |
| empty | 0 | 0 | 0 | No eligible nodes; no phantom row or spacer. |

Overall includes both subjects, Subset includes subject 01, and Empty includes
neither. `metadata.R` stores literal expected labels, cells and runtime IDs.
For example, group A has VALUE1 mean 3.0 and VALUE2 mean 13.0; its subset means
are 2.0 and 12.0. Empty continuous cells are NE; empty categorical counts are 0.

From the repository root:

```text
Rscript test/fixtures/sas/hierarchical_row_assembly/build_sources.R
Rscript -e "testthat::test_dir('test/testthat', filter='z-hierarchical-row-assembly', reporter='summary')"
```

The builder preserves the generated program through final table assembly and
omits only the subsequent RTF report section. Source files and expectations
are written to ignored `generated/`. R tests verify source generation only;
their success does not establish SAS runtime correctness.

For external SAS 9.4 verification, use this fixture directory as the working
directory, create `logs/`, and run each case in a fresh process:

```text
sas.exe -sysin run_case.sas -sysparm basic -log logs/basic.log -print logs/basic.lst
sas.exe -sysin run_case.sas -sysparm sorted -log logs/sorted.log -print logs/sorted.lst
sas.exe -sysin run_case.sas -sysparm multilevel -log logs/multilevel.log -print logs/multilevel.lst
sas.exe -sysin run_case.sas -sysparm mixed -log logs/mixed.log -print logs/mixed.lst
sas.exe -sysin run_case.sas -sysparm empty -log logs/empty.log -print logs/empty.lst
```

Each case must exit successfully with `[FIXTURE] row assembly <case> passed`,
without SAS errors. Assertions check one cell per row/column, absolute wide
rows in observation order, the non-spacer final rows, and spacer counts,
positions and empty text. No shared/independent execution result is used as
the expected output. The pre-fix generator fails the basic row-identity/width
checks even when its long-cell count is 12.

Runtime verification (2026-09-29): all five cases passed on SAS 9.4, with exit
code 0, the expected completion marker, and no SAS errors. The local SAS
installation reports a SASHELP concatenation warning on startup; the empty
case also reports that PROC COMPARE has no matching observations. Explicit
cell/assembly count checks still pass for the empty case.
An ignored generated copy with the old SET statement produced two wide rows
and failed `row_identity_or_column_collision` (exit 2), confirming that the
new assertions detect the original defect.

## Reproducible performance comparison

Run from the repository root:

```text
Rscript test/fixtures/sas/hierarchical_row_assembly/build_benchmark.R
powershell -File test/fixtures/sas/hierarchical_row_assembly/run_benchmark.ps1
```

Pass `-SasExecutable` if SAS is not on PATH. This is an external fixture tool,
not an application feature. It uses 10,000 and 30,000 synthetic records, ten
nodes, two or four continuous blocks, and Overall/half-population/Empty columns.
Each mode runs three times in fresh SAS processes, alternating mode order.
The independent path uses the existing alternate-emitter hook. Source analysis
and table assembly are timed together; SAS startup, synthetic data creation,
result persistence and report generation are excluded.

The R builder also prints physical source lines and DATA/PROC step counts for
both modes. Run just the first command to compare source size without running
SAS. Counts include comments and blank lines and exclude the RTF report section;
fewer procedure calls alone do not establish shorter source or faster execution.

Space is the sum of `dictionary.tables.filesize` for the generated `_TFL_*`
WORK tables at the end of generation. It is not peak WORK consumption, process
memory or total I/O. The runner saves samples in `generated/benchmark-results.json`
and compares each configuration's last shared/independent wide and statistic
outputs exactly. See `docs/hierarchical-runtime-verification.md` in the project
for measured results and limits. Generated sources, datasets and external logs
remain ignored and must not be committed.
