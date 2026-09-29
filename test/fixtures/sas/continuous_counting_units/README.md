# Hierarchical continuous counting-unit SAS fixture

This fixture validates the generated SAS implementation of hierarchical
continuous counting units using small synthetic `WORK` datasets. It does not
read study data or require permanent SAS datasets.

Covered behavior:

- `record`: every source record remains an analysis observation;
- `distinct_subject`: one nonmissing value plus missing records resolves to
  the unique nonmissing value, while multiple missing records collapse to one
  missing unit;
- `distinct_key`: the same rules apply to the typed character/numeric key
  `USUBJID AVISITN`;
- `shared_level`: continuous and categorical blocks anchored at the same level
  consume one shared `_TFL_HMERGE` membership expansion while retaining
  independent analysis procedures and results;
- conflicting nonmissing values for one `distinct_subject` unit write
  `ERROR: [USER] continuous_unit_multiple_values` and execute `ABORT CANCEL`.

## Build generated programs

From the repository root:

```text
Rscript test/fixtures/sas/continuous_counting_units/build_sources.R
```

This writes current generator output to the ignored `generated/` directory.
Re-run the command whenever emitter code changes.

## Run in SAS 9.4

Start SAS with this fixture directory as the working directory. Run the three
passing programs separately:

```text
sas.exe -sysin run_record.sas
sas.exe -sysin run_distinct_subject.sas
sas.exe -sysin run_distinct_key.sas
sas.exe -sysin run_shared_level.sas
```

Each successful log must contain its `[FIXTURE] ... passed` message and no SAS
`ERROR:` messages.

Run the expected-failure case in a separate SAS process:

```text
sas.exe -sysin run_distinct_subject_conflict.sas
```

This run passes only when the log contains:

```text
ERROR: [USER] continuous_unit_multiple_values
```

and the SAS submission is cancelled before the fallback
`fixture_expected_abort_missing` message can execute.

Generated `.sas` programs, `.log`, `.lst`, and `.rtf` files are runtime
artifacts and must not be committed.
