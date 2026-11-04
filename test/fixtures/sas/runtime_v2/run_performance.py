"""Bounded format-width comparison using isolated source trees and equal results."""
from pathlib import Path
import argparse
import io
import json
import re
import shutil
import statistics
import subprocess
import zipfile

from runner import run_sas, sha256, write_json
from run_formats import read_table

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    args = parser.parse_args()
    target = ROOT / "study/validation_v2/runs" / args.batch / "performance"
    target.mkdir(parents=True, exist_ok=False)
    old = subprocess.check_output(["git", "archive", "--format=zip", "cd716d0", "src"], cwd=ROOT)
    for version in ["before", "current"]:
        context = target / version / "build_context"
        context.mkdir(parents=True)
        if version == "before":
            zipfile.ZipFile(io.BytesIO(old)).extractall(context)
        else:
            shutil.copytree(ROOT / "src", context / "src")
        fixtures = context / "test/fixtures/sas/runtime_v2"
        fixtures.mkdir(parents=True)
        for name in ["support.R", "format_cases.R", "build_performance.R"]:
            shutil.copy2(Path(__file__).parent / name, fixtures / name)
        write_json(context / "source_hashes.json", {str(p.relative_to(context)): sha256(p) for p in (context / "src").rglob("*.R")})
        for records in [120, 600]:
            generated = target / version / str(records)
            built = subprocess.run(["Rscript", str(fixtures / "build_performance.R"), str(generated), str(records)],
                                   cwd=context, capture_output=True, text=True, encoding="utf-8", errors="replace")
            (context / f"build_{records}.log").write_text(built.stdout+built.stderr, encoding="utf-8")
            assert built.returncode == 0
    outcomes = []
    for records in [120, 600]:
        for repeat in range(1,4):
            frames = {}
            for version in (["before", "current"] if repeat % 2 else ["current", "before"]):
                output = target / version / str(records) / str(repeat)
                (output / "results").mkdir(parents=True)
                shutil.copy2(output.parent / "program.sas", output / "program.sas")
                (output / "run.sas").write_text(f'''options nosource nosource2 fullstimer;
libname results "{(output / 'results').as_posix()}";
%include "program.sas";
%include "{(ROOT / 'test/fixtures/sas/runtime_v2/snapshot.sas').as_posix()}";
%put NOTE: [RUNTIME] complete;
''', encoding="utf-8")
                execution = run_sas(output, timeout=240)
                assert execution["process_checks_passed"], str(output)
                log = (output / "run.log").read_text(encoding="utf-8-sig")
                seconds = float(re.search(r"NOTE: \[PERFORMANCE\] analysis_seconds=([\d.]+)", log)[1])
                inventory = read_table(output / "results", "table_inventory")
                columns = read_table(output / "results", "column_inventory")
                widths = columns[columns.memname.eq("_TFL_HNODES_001_001") & columns.name.isin(["node_key", "node_label", "node_order_path"])]
                frames[version] = read_table(output / "results", "_tfl_asm_001")
                result = dict(version=version, input_records=records, repeat=repeat, analysis_seconds=seconds,
                              final_work_bytes=int(inventory.filesize.sum()),
                              node_widths=dict(zip(widths.name, widths.length.astype(int))))
                outcomes.append(result)
                print(result, flush=True)
            fields = ["label", "col_001", "row_role", "indent_level", "node_key", "report_order"]
            assert frames["before"][fields].equals(frames["current"][fields])
            for result in outcomes[-2:]:
                result["results_equal"] = True
            write_json(target / "measurements.json", outcomes)
    summary = []
    for records in [120,600]:
        metrics = {}
        for version in ["before", "current"]:
            cases = [c for c in outcomes if c["version"]==version and c["input_records"]==records]
            metrics[version] = dict(median_seconds=statistics.median(c["analysis_seconds"] for c in cases),
                                    median_final_work_bytes=statistics.median(c["final_work_bytes"] for c in cases),
                                    node_widths=cases[0]["node_widths"])
        summary.append(dict(input_records=records, **metrics))
    write_json(target / "summary.json", {"before_commit": "cd716d0", "measurements": summary,
               "limitations": "Final WORK dataset bytes, not peak disk or memory. Three local elapsed-time trials; no general throughput claim."})


if __name__ == "__main__":
    main()
