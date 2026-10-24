# FDA 2025 Integrated Safety Tables reference

Source reviewed:

- FDA, *Standard Safety Tables and Figures: Integrated Guide*;
- Version 2.0;
- Version date: April 2025;
- official download: <https://www.fda.gov/media/187065/download>.

The guide is a table-shell and analysis-planning reference. It does not
change this project's source-only boundary: the application preserves SAS
expressions and dataset references but does not read or execute analysis data.

## Selected table patterns

### Table 2: Demographics and Baseline Clinical Characteristics

This is a suitable multi-chunk baseline template:

- continuous rows such as age, weight, height;
- categorical rows such as sex, race, and ethnicity;
- treatment-arm columns represented by header conditions;
- continuous statistics commonly include `n`, `mean`, `sd`, and quartiles;
- categorical cells commonly include `n (%)`.

### Tables 10 and 14: Adverse events by SOC and preferred term

These map to a hierarchical template:

- level 1: system organ class (`SOC`);
- level 2: preferred term (`PT`);
- analysis rows for severity, seriousness, or treatment-emergent criteria;
- categorical `n` and `pct` statistics within treatment/header columns.

### Table 35: Mean change from baseline over time

This is the most useful visit/timepoint pattern for the current model:

- parameter level, for example `PARAMCD`;
- nested study-visit level, for example `AVISIT`/`AVISITN`;
- continuous analysis variable such as `AVAL` or a change-from-baseline value;
- cells may contain `n (%)`, mean change, and confidence-interval text;
- treatment arms are represented by header columns.

The current contract can represent the parameter/visit hierarchy and the
continuous `n`, `mean`, and `sd` parts. Confidence intervals and explicit
derived change-from-baseline variables remain caller-defined SAS expressions
or future statistic extensions; no unsupported statistic IDs are added to the
fixture.

## Current synthetic fixture coverage

`assets/demo_metadata.zip` includes:

- baseline characteristics (Table 2 style);
- AE by SOC/PT and severity (Tables 10/14 style);
- parameter/visit vital-sign summary with relative digits (Table 35 style).

The fixture is synthetic and contains no patient-level data.
