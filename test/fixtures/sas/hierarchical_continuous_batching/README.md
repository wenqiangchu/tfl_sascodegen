# Shared hierarchical continuous analysis fixture

These synthetic WORK-only fixtures compare the generated shared `PROC MEANS`
and value/digits conversion with independent block execution through an alternate registered emitter.
They do not read study data or add SAS execution to the application.

From the repository root, build the paired programs:

```text
Rscript test/fixtures/sas/hierarchical_continuous_batching/build_sources.R
```

Start SAS 9.4 with this fixture directory as its working directory. Run each
case in a fresh process, directing log/listing files to the ignored `logs/`
directory (create it first):

```text
sas.exe -sysin run_success.sas -sysparm record -log logs/record.log -print logs/record.lst
sas.exe -sysin run_success.sas -sysparm four -log logs/four.log -print logs/four.lst
sas.exe -sysin run_success.sas -sysparm varied -log logs/varied.log -print logs/varied.lst
sas.exe -sysin run_success.sas -sysparm negative -log logs/negative.log -print logs/negative.lst
sas.exe -sysin run_success.sas -sysparm subject -log logs/subject.log -print logs/subject.lst
sas.exe -sysin run_success.sas -sysparm key -log logs/key.log -print logs/key.lst
sas.exe -sysin run_success.sas -sysparm empty -log logs/empty.log -print logs/empty.lst
sas.exe -sysin run_success.sas -sysparm missing -log logs/missing.log -print logs/missing.lst
sas.exe -sysin run_conflict.sas -sysparm subject_conflict -log logs/subject_conflict.log
sas.exe -sysin run_conflict.sas -sysparm key_conflict -log logs/key_conflict.log
```

Cases other than `negative` and the two conflicts must exit with code 0, contain their `[FIXTURE] ... passed`
marker, and have no SAS `ERROR:` messages. All eight raw statistics, precision,
hierarchical statistic identities, and final logical cells must match the
independent path. Coverage includes two different analysis variables, repeated
local row IDs, second-block result sorting, same-row/below placement, overlapping
and empty header columns, all-missing values, no source records, and mixed
character/numeric distinct keys (including numeric special missing values).
The `four` case uses four distinct analysis variables and requires eight wide
rows, exercising every output of the shared raw split. The fixture removes its
generated `_TFL_*` WORK tables after saving the independent baseline so stale
outputs cannot conceal an omitted shared result. Synthetic inputs and the
saved `hb_base_*` comparison tables remain available.

Private STAT and REND values are compared in addition to the container results.
The descriptors of KEY_MAP, KEY, CJOIN, STAT, RSTAT, and REND must match by column
name, position, type, length, format, informat, and label. Private STAT retains
all 32 columns, with no routing flags or extra shared identity fields.

The `varied` case adds a long label row and a count-only row to the second block,
reverses its statistic order, and uses a different cell format. It must produce
eight wide rows. The `negative` case requests n, mean with relative digits -9,
and max with one decimal place. It must reach its completion marker and pass
all comparisons while emitting exactly 12 occurrences of
`ERROR: [USER] Relative digits resolved to a negative value.` per execution
path (24 in total). The `begin independent` / `begin shared` log markers delimit
the paths. SAS may append an error-page summary. These expected diagnostics must
not be classified as a clean log; any other error before completion is a failure.
On the verified local SAS 9.4 installation this case exits 0 despite the explicit
ERROR messages, so exit status alone is not its oracle.

Both conflict cases have a valid first block and two equal nonmissing records
in the second block. They must exit with the expected SAS cancellation, report
`continuous_unit_multiple_values`, and stop before the shared MEANS procedure
or `expected_second_block_abort_missing` fallback executes. Duplicate source
warnings are disabled to ensure this option never disables the unit guard.

Generated source, logs, listings, and report files are ignored local artifacts.
Only the hand-authored fixture inputs, assertions, and builder belong in Git.
