"""Execute format fixtures and compare literal expectations with saved SAS data."""
from pathlib import Path
import argparse
import json
import re
import shutil
import sys

import pandas as pd

from runner import run_sas, write_json

ROOT = Path(__file__).resolve().parents[4]


def read_table(directory, name):
    return clean_table(pd.read_sas(directory / (name.lower() + ".sas7bdat"), encoding="utf-8"))


def clean_table(frame):
    # pandas represents SAS blank character values as NaN; numeric missing stays NaN.
    for column in frame.select_dtypes(include="object"):
        frame[column] = frame[column].fillna("")
    return frame


def verify(case, output, expected):
    checks = []

    def check(name, passed, detail=None):
        checks.append({"check": name, "passed": bool(passed), "detail": detail})

    results = output / "results"
    headers = read_table(results, "_TFL_HN_001").sort_values("column_order")
    check("header_n", headers.header_n.tolist() == expected["header_n"])
    nodes = clean_table(pd.concat([pd.read_sas(p, encoding="utf-8") for p in sorted(results.glob("_tfl_hnodes_*.sas7bdat"))], ignore_index=True))
    paths = {"": ""}
    for _, row in nodes.sort_values("hierarchy_level", kind="stable").iterrows():
        paths[row.node_key] = "/".join(filter(None, [paths[row.parent_node_key], row.node_label]))
    actual_paths = [paths[key] for key in nodes.node_key]
    check("complete_node_domain", sorted(actual_paths) == sorted(expected["expected_counts"]), actual_paths)
    check("unique_node_identity", len(set(nodes.node_key)) == len(nodes))
    assembled = read_table(results, "_TFL_ASM_001")
    rows = assembled[assembled.row_role != "spacer"]
    check("one_report_row_per_node", len(rows) == len(expected["expected_counts"]))
    expected_order = expected["expected_order"]
    actual_order = [paths.get(key) for key in rows.node_key if paths.get(key) in expected_order]
    check("format_or_result_display_order", actual_order == expected_order, actual_order)
    for _, row in rows.iterrows():
        path = paths.get(row.node_key)
        check("known_report_node", path in expected["expected_counts"], path)
        if path not in expected["expected_counts"]:
            continue
        for index, count in enumerate(expected["expected_counts"][path], 1):
            denominator = expected["header_n"][index - 1]
            pct = f"{100 * count / denominator:.1f}" if denominator else "NE"
            check("cell", row[f"col_{index:03d}"] == f"{count}|{pct}",
                  {"path": path, "column": index, "actual": row[f"col_{index:03d}"], "expected": f"{count}|{pct}"})
    log = (output / "run.log").read_text(encoding="utf-8-sig")
    # NOSOURCE prevents the generated PUTLOG statement itself being counted.
    check("missing_warning_count", log.count("WARNING: [USER] missing_level") == expected["expected_missing_warnings"])
    # A PROC SORT BY variable that its level never creates fails at compile time with
    # an ERROR naming that variable. Match the name rather than the localized wording,
    # so a missing sort key is reported as its own failure instead of a bare error count.
    program = (output / "program.sas").read_text(encoding="utf-8-sig")
    sort_keys = set()
    for block in re.findall(r"proc sort[^;]*;(.*?)\b(?:run|quit)\s*;", program, re.S | re.I):
        for by in re.findall(r"\bby\b([^;]*);", block, re.S | re.I):
            sort_keys.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", by))
    error_lines = [line for line in log.splitlines() if line.startswith("ERROR")]
    undefined = sorted(
        key for key in sort_keys
        if any(re.search(rf"(?i)\b{re.escape(key)}\b", line) for line in error_lines)
    )
    check("sort_key_defined", not undefined, undefined)
    write_json(output / "assertions.json", checks)
    return all(item["passed"] for item in checks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--case")
    args = parser.parse_args()
    workspace = ROOT / "study/validation_v2"
    outcomes = []
    for fixture in sorted((workspace / "synthetic").iterdir()):
        if not fixture.is_dir() or (args.case and fixture.name != args.case):
            continue
        output = workspace / "runs" / args.batch / "synthetic" / fixture.name
        if (output / "execution.json").exists():
            raise RuntimeError(f"Run already exists: {output}")
        (output / "results").mkdir(parents=True, exist_ok=True)
        shutil.copy2(fixture / "program.sas", output / "program.sas")
        wrapper = f'''options nosource nosource2;
libname results "{(output / 'results').as_posix()}";
%include "program.sas";
%include "{(ROOT / 'test/fixtures/sas/runtime_v2/snapshot.sas').as_posix()}";
%put NOTE: [RUNTIME] complete;
'''
        (output / "run.sas").write_text(wrapper, encoding="utf-8")
        execution = run_sas(output)
        try:
            assertions_passed = verify(fixture.name, output, json.loads((fixture / "expected.json").read_text()))
        except Exception as error:
            assertions_passed = False
            write_json(output / "verification_error.json", {"type": type(error).__name__, "message": str(error)})
        outcome = {"case": fixture.name, "process_checks_passed": execution["process_checks_passed"],
                   "assertions_passed": assertions_passed}
        outcomes.append(outcome)
        print(outcome, flush=True)
        write_json(workspace / "runs" / args.batch / "format_results.json", outcomes)
    if not outcomes or not all(c["process_checks_passed"] and c["assertions_passed"] for c in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
