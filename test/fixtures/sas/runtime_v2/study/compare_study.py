"""Compare historical and current SAS results without treating old assembly as truth."""
from pathlib import Path
import argparse
import json
import sys

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "test/fixtures/sas/runtime_v2"))
from runner import write_json
from run_formats import clean_table


def read(path):
    return clean_table(pd.read_sas(path, encoding="utf-8"))


def compare(left, right, keys, columns, optional_columns=()):
    optional_columns = set(optional_columns)
    missing_left = sorted(set(keys + columns) - set(left.columns))
    missing_right = sorted(set(keys + columns) - set(right.columns))
    absent_from_both = sorted(optional_columns - set(left.columns) - set(right.columns))
    missing_left = [column for column in missing_left if column not in absent_from_both]
    missing_right = [column for column in missing_right if column not in absent_from_both]
    asymmetric_optional = sorted(
        column for column in optional_columns
        if (column in left.columns) != (column in right.columns)
    )
    if asymmetric_optional:
        missing_left += [c for c in asymmetric_optional if c not in left.columns]
        missing_right += [c for c in asymmetric_optional if c not in right.columns]
    if missing_left or missing_right:
        return {
            "passed": False,
            "left_rows": len(left),
            "right_rows": len(right),
            "columns": columns,
            "keys": keys,
            "missing_left": missing_left,
            "missing_right": missing_right,
            "absent_from_both": absent_from_both,
            "differences": [{
                "reason": "required comparison fields are missing",
                "missing_left": missing_left,
                "missing_right": missing_right,
            }],
        }
    left = left.sort_values(keys, kind="stable").reset_index(drop=True)
    right = right.sort_values(keys, kind="stable").reset_index(drop=True)
    differences = []
    if len(left) != len(right):
        return {"passed": False, "left_rows": len(left), "right_rows": len(right), "columns": columns}
    compared_columns = [column for column in columns if column not in absent_from_both]
    for column in compared_columns:
        if pd.api.types.is_numeric_dtype(left[column]) and pd.api.types.is_numeric_dtype(right[column]):
            # Counts are integral and compared exactly; unrounded floating statistics
            # permit 1e-12 absolute error only, with no relative allowance.
            tolerance = 0 if column in ("numerator", "denominator", "header_n", "_n", "count", "estimable", "resolved_digits") else 1e-12
            if column == "value" and "statistic_id" in left:
                tolerance = np.where(left.statistic_id.eq("n"), 0, 1e-12)
            same = np.isclose(left[column], right[column], atol=tolerance, rtol=0, equal_nan=True)
        else:
            same = (left[column].fillna("") == right[column].fillna("")).to_numpy()
        if not same.all():
            differences.append({"column": column, "mismatches": int((~same).sum())})
    return {"passed": not differences, "left_rows": len(left), "right_rows": len(right),
            "columns": compared_columns, "keys": keys, "differences": differences,
            "missing_left": [], "missing_right": [], "absent_from_both": absent_from_both}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--baseline-batch")
    args = parser.parse_args()
    batch = ROOT / "study/validation_v2/runs" / args.batch
    summary = []
    for case in sorted(batch.glob("*__*")):
        baseline = ROOT / "study/validation_v2/runs" / (args.baseline_batch or args.batch) / case.name
        left_dir, right_dir = baseline / "baseline/results", case / "current/results"
        checks = []
        files = ["_tfl_hn_001.sas7bdat"]
        files += [p.name for p in left_dir.glob("_tfl_stat_*.sas7bdat")]
        files += [p.name for p in left_dir.glob("_tfl_hnodes_*.sas7bdat")]
        for filename in files:
            left, right = read(left_dir / filename), read(right_dir / filename)
            if "stat_" in filename:
                keys = ["chunk_id", "node_key", "row_id", "header_column_id", "statistic_id"]
                columns = keys + ["analysis_id", "value", "estimable", "resolved_digits", "numerator", "denominator",
                                  "_n", "_mean", "_sd", "_median", "_q1", "_q3", "_min", "_max"]
                # Statistic columns are per chunk type: categorical chunks carry none of
                # the continuous summaries. Absence is only a regression when it becomes
                # asymmetric, so these are optional and reported through absent_from_both.
                optional = ["analysis_id", "numerator", "denominator",
                            "_n", "_mean", "_sd", "_median", "_q1", "_q3", "_min", "_max"]
            elif "hnodes_" in filename:
                keys = ["node_key"]
                columns = ["node_key", "node_label", "parent_node_key", "hierarchy_level"]
                checks.append({"dataset": filename + "_historical_order", **compare(left, right, keys, ["node_order_path"])})
                optional = []
            else:
                keys, columns = ["column_order"], ["column_order", "header_n"]
                optional = []
            checks.append({"dataset": filename, **compare(left, right, keys, columns, optional)})
        left, right = read(left_dir / "_tfl_cells_001.sas7bdat"), read(right_dir / "_tfl_cells_001.sas7bdat")
        keys = ["chunk_id", "runtime_row_id", "header_column_id"]
        checks.append({"dataset": "logical_cells", **compare(left, right, keys,
                      keys + ["label", "indent_level", "row_role", "cell_text", "node_key"])})
        left, right = read(left_dir / "_tfl_asm_001.sas7bdat"), read(right_dir / "_tfl_asm_001.sas7bdat")
        columns = [f"col_{index:03d}" for index in range(1, 5)] + [
            "label", "indent_level", "row_role", "node_key", "runtime_row_id", "chunk_order", "row_sequence", "report_order"]
        assembly = compare(left, right, ["report_order"], columns)
        independent_path = case / "independent_assertions.json"
        independent = independent_path.exists() and all(c["passed"] for c in json.loads(independent_path.read_text()))
        historical_checks = [c for c in checks if c["dataset"].endswith("_historical_order")]
        regular_checks = [c for c in checks if not c["dataset"].endswith("_historical_order")]
        historical_order_equal = all(c["passed"] for c in historical_checks)
        analysis_equal = all(c["passed"] for c in regular_checks)
        result = {"case": case.name, "analysis_and_logical_cells_equal": analysis_equal,
                  "historical_order_equal": historical_order_equal,
                  "analysis_checks": checks, "assembly": assembly,
                  "passed": analysis_equal and historical_order_equal and assembly["passed"],
                  "assembly_difference_classification": "none" if assembly["passed"] else
                  ("Historical row_sequence and inherited sibling counter defects corrected; independent source-data oracle passed."
                   if independent else "Unresolved: independent assembly proof missing or failing.")}
        write_json(case / "comparison.json", result)
        summary.append(result)
        print(case.name, "analysis/cells", result["analysis_and_logical_cells_equal"],
              "assembly", assembly["passed"], "rows", len(left), len(right))
    write_json(batch / "comparisons.json", summary)
    if not all(result["passed"] for result in summary):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
