"""Check independent literal numerator/denominator counts and displayed percentages."""
from pathlib import Path
import argparse
import json
import shutil

import pandas as pd

from runner import run_sas, write_json
from run_formats import read_table, clean_table

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--fixture", default="denominators", choices=["denominators", "severity_case"])
    args = parser.parse_args()
    fixture = ROOT / "study/validation_v2" / args.fixture
    output = ROOT / "study/validation_v2/runs" / args.batch / args.fixture
    (output / "results").mkdir(parents=True, exist_ok=False)
    shutil.copy2(fixture / "program.sas", output / "program.sas")
    (output / "run.sas").write_text(f'''options nosource nosource2;
libname results "{(output / 'results').as_posix()}";
%include "program.sas";
%include "{(ROOT / 'test/fixtures/sas/runtime_v2/snapshot.sas').as_posix()}";
%put NOTE: [RUNTIME] complete;
''', encoding="utf-8")
    execution = run_sas(output)
    expected = json.loads((fixture / "expected.json").read_text())
    results = output / "results"
    nodes = pd.concat([read_table(results, p.stem) for p in results.glob("_tfl_hnodes_*.sas7bdat")], ignore_index=True)
    labels = {"": ""}
    for _, node in nodes.sort_values("hierarchy_level", kind="stable").iterrows():
        labels[node.node_key] = "/".join(filter(None, [labels[node.parent_node_key], node.node_label]))
    statistics = []
    for p in results.glob("_tfl_stat_*.sas7bdat"):
        frame = read_table(results, p.stem)
        if "denominator" in frame and "analysis_id" not in frame:
            statistics.append(frame)
    stats = pd.concat(statistics, ignore_index=True)
    assembled = read_table(results, "_TFL_ASM_001")
    checks = []
    def check(name, passed, detail=None):
        checks.append({"check": name, "passed": bool(passed), "detail": detail})
    check("process", execution["process_checks_passed"])
    header = read_table(results, "_TFL_HN_001").sort_values("column_order")
    check("unchanged_header_n", header.header_n.tolist() == expected["header_n"])
    stats["path"] = stats.node_key.map(labels)
    assembled["path"] = assembled.node_key.map(labels)
    check("statistic_cardinality", len(stats) == len(expected["expected"]) * 3 * 2)
    for row in expected["expected"]:
        for col in range(1,4):
            n, den = row["n"][col-1], row["denominator"][col-1]
            actual = stats[(stats.row_id == row["row_id"]) & (stats.path == row["path"]) & (stats.column_order == col)]
            detail = {"row_id": row["row_id"], "path": row["path"], "column": col}
            check("raw_counts", len(actual) == 2 and (actual.numerator == n).all() and (actual.denominator == den).all(), detail)
            cell = assembled[(assembled.row_id == row["row_id"]) & (assembled.path == row["path"]) & (assembled.row_role != "spacer")]
            pct = f"{100*n/den:.1f}" if den else "NE"
            check("rendered_cell", len(cell) == 1 and cell.iloc[0][f"col_{col:03d}"] == f"{n}|{pct}", detail)
    write_json(output / "assertions.json", checks)
    print("Denominator assertions:", len(checks), "failed:", sum(not c["passed"] for c in checks))
    if not all(c["passed"] for c in checks):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
