"""Independent hierarchy oracle using source data and explicit study rules."""
from pathlib import Path
import argparse
import json
import sys
from decimal import Decimal, ROUND_HALF_UP

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "test/fixtures/sas/runtime_v2"))
from runner import write_json
from run_formats import read_table, clean_table


def source(name):
    data = clean_table(pd.read_sas(ROOT / "study/sas_data" / (name + ".sas7bdat"), encoding="utf-8"))
    for col in data.select_dtypes(include="object"):
        data[col] = data[col].str.rstrip()
    return data


def fmt(value, digits):
    if pd.isna(value):
        return "NE"
    # SAS ROUND treats near-decimal halfway values as ties. Remove only the
    # reference calculation's floating noise (raw values still checked at 1e-12).
    return format(Decimal(str(round(value, 12))).quantize(Decimal(10) ** -digits, rounding=ROUND_HALF_UP), "f")


def expected(case):
    adsl = source("adsl")
    adsl = adsl[adsl.SAFFL == "Y"]
    assert adsl.USUBJID.is_unique
    groups = [set(adsl.loc[adsl.TRT01A == treatment, "USUBJID"]) for treatment in
              ["Placebo", "Xanomeline Low Dose", "Xanomeline High Dose"]] + [set(adsl.USUBJID)]
    laboratory = case == "legacy__14.3.2.1"
    if laboratory:
        data = source("adlbh")
        data = data[(data.SAFFL == "Y") & (data.ANL01FL == "Y")]
        levels = [("PARAMCD", "PARAM", "PARAMN", True), ("AVISIT", "AVISIT", "AVISITN", True)]
    else:
        data = source("adae")
        data = data[(data.SAFFL == "Y") & (data.TRTEMFL == "Y")]
        if case == "severity__14.3.1.4":
            data = data[(data[["USUBJID", "TRTA", "AEBODSYS", "AEDECOD"]] != "").all(axis=1)].copy()
            data["severity_rank"] = data.AESEV.str.upper().map({"MILD": 1, "MODERATE": 2, "SEVERE": 3})
            data = data.dropna(subset=["severity_rank"])
            # Independent group maximum reproduces the historical PT-scoped preparation.
            data = data.groupby(["USUBJID", "TRTA", "AEBODSYS", "AEDECOD"], as_index=False).severity_rank.max()
            data["AESEV_MAX"] = data.severity_rank.map({1: "MILD", 2: "MODERATE", 3: "SEVERE"})
            levels = [("AESEV_MAX", "AESEV_MAX", "severity_rank", False),
                      ("AEBODSYS", "AEBODSYS", "AEBODSYS", True), ("AEDECOD", "AEDECOD", "AEDECOD", True)]
        else:
            levels = [("AEBODSYS", "AEBODSYS", "AESOCCD", True), ("AEDECOD", "AEDECOD", "AEPTCD", True)]
    data = data[data.USUBJID.isin(groups[-1])]
    rows, raw = [], []

    def walk(frame, depth, path):
        key, label, order, asc = levels[depth]
        frame = frame[frame[key].notna() & (frame[key] != "")]
        descriptors = frame[list(dict.fromkeys([key, label, order]))].drop_duplicates()
        assert descriptors[key].is_unique, "Input has conflicting labels/orders"
        descriptors = descriptors.sort_values(list(dict.fromkeys([order, key])), ascending=asc, kind="stable")
        for _, descriptor in descriptors.iterrows():
            group = frame[frame[key] == descriptor[key]]
            current_path = path + [str(descriptor[label])]
            rows.append(dict(label=str(descriptor[label]), indent_level=depth, hierarchy_level=depth+1,
                             row_role="dynamic", cells=[""]*4, path=current_path))
            if depth+1 < len(levels):
                walk(group, depth+1, current_path)
            else:
                cells = []
                for index, subjects in enumerate(groups, 1):
                    eligible = group[group.USUBJID.isin(subjects)]
                    if laboratory:
                        values = eligible.AVAL.dropna()
                        n, mean, sd = len(values), values.mean(), values.std(ddof=1)
                        cells.append(f"{n} {fmt(mean, 1)} ({fmt(sd, 2)})")
                        raw.append(dict(path=current_path, column_order=index, _n=n, _mean=mean, _sd=sd))
                    else:
                        n = eligible.USUBJID.nunique()
                        cells.append(str(n))
                        raw.append(dict(path=current_path, column_order=index, numerator=n, denominator=n))
                rows.append(dict(label="Observed value" if laboratory else "Subjects",
                                 indent_level=depth+1+int(laboratory), hierarchy_level=depth+1,
                                 row_role="static", cells=cells, path=current_path))
    walk(data, 0, [])
    spaced = []
    for i, row in enumerate(rows):
        if i and row["hierarchy_level"] != rows[i-1]["hierarchy_level"]:
            spaced.append(dict(label="", indent_level=0, hierarchy_level=row["hierarchy_level"],
                               row_role="spacer", cells=[""]*4, path=row["path"]))
        spaced.append(row)
    return spaced, raw, [len(g) for g in groups]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    args = parser.parse_args()
    batch = ROOT / "study/validation_v2/runs" / args.batch
    outcomes = []
    for case in ["legacy__14.3.1.2", "legacy__14.3.2.1", "severity__14.3.1.4"]:
        rows, raw, hn = expected(case)
        result_dir = batch / case / "current/results"
        actual = read_table(result_dir, "_tfl_asm_001").sort_values("report_order")
        checks = []
        def check(name, passed, detail=None):
            checks.append(dict(check=name, passed=bool(passed), detail=detail))
        check("header_n", read_table(result_dir, "_tfl_hn_001").sort_values("column_order").header_n.tolist() == hn)
        check("assembly_row_count", len(rows) == len(actual), {"expected": len(rows), "actual": len(actual)})
        for index, (exp, (_, got)) in enumerate(zip(rows, actual.iterrows())):
            for field in ["label", "indent_level", "hierarchy_level", "row_role"]:
                check("assembly_"+field, exp[field] == got[field], {"row": index+1, "expected": exp[field], "actual": got[field]})
            check("assembly_cells", exp["cells"] == [got[f"col_{i:03d}"] for i in range(1,5)],
                  {"row": index+1, "expected": exp["cells"], "actual": [got[f"col_{i:03d}"] for i in range(1,5)]})
        nodes = pd.concat([read_table(result_dir, p.stem) for p in result_dir.glob("_tfl_hnodes_*.sas7bdat")], ignore_index=True)
        paths = {"": []}
        for _, node in nodes.sort_values("hierarchy_level", kind="stable").iterrows():
            paths[node.node_key] = paths[node.parent_node_key] + [node.node_label]
        check("independent_node_domain", sorted([p for p in paths.values() if p], key=str) == sorted([r["path"] for r in rows if r["row_role"]=="dynamic"], key=str))
        stat = read_table(result_dir, "_tfl_stat_002")
        stat["path"] = stat.node_key.map(lambda key: tuple(paths[key]))
        for exp in raw:
            part = stat[(stat.path == tuple(exp["path"])) & (stat.column_order == exp["column_order"])]
            for field, value in exp.items():
                if field in ("path", "column_order"):
                    continue
                tolerance = 1e-12 if field in ("_mean", "_sd") else 0
                observed = part[field].fillna(0) if field == "_n" else part[field]
                check("independent_"+field, len(part)>0 and np.isclose(observed, value, atol=tolerance, rtol=0, equal_nan=True).all(),
                      {"path": exp["path"], "column": exp["column_order"]})
        write_json(batch / case / "independent_assertions.json", checks)
        write_json(batch / case / "expected_assembly.json", rows)
        outcome = dict(case=case, assertions=len(checks), failed=sum(not c["passed"] for c in checks))
        outcomes.append(outcome)
        print(outcome, flush=True)
    write_json(batch / "independent_results.json", outcomes)
    if any(c["failed"] for c in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
