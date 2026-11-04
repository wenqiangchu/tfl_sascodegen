"""Run isolated historical/current study programs and preserve all source inputs."""
from pathlib import Path
import argparse
import difflib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "test/fixtures/sas/runtime_v2"))
from runner import run_sas, sha256, write_json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--mode", choices=["baseline", "current", "both"], default="both")
    parser.add_argument("--case")
    args = parser.parse_args()
    workspace = ROOT / "study/validation_v2"
    batch = workspace / "runs" / args.batch
    batch.mkdir(parents=True, exist_ok=True)
    cases = json.loads((workspace / "cases.json").read_text())
    inputs = list((ROOT / "study/sas_data").glob("*.sas7bdat"))
    inputs += [ROOT / item["old_program"] for item in cases]
    inputs += [ROOT / item["old_rtf"] for item in cases]
    inputs += list((workspace / "bundles").glob("*/original_v1.zip"))
    before = {str(path.relative_to(ROOT)): sha256(path) for path in inputs}
    write_json(batch / "inputs.json", before)
    write_json(batch / "git.json", {
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "diff": subprocess.check_output(["git", "diff"], cwd=ROOT, text=True),
    })
    outcomes = []
    for case in cases:
        if args.case and case["case_id"] != args.case:
            continue
        original = (ROOT / case["old_program"]).read_text(encoding="utf-8-sig")
        # The wrapper owns STUDY and binds it read-only. No analysis lines change.
        baseline, replacements = re.subn(r"(?im)^libname\s+study\s+[^;]+;", "", original)
        current = (workspace / "generated" / case["case_id"] / "report.sas").read_text(encoding="utf-8")
        diff_dir = batch / case["case_id"]
        diff_dir.mkdir(parents=True, exist_ok=True)
        (diff_dir / "source.diff").write_text("".join(difflib.unified_diff(
            baseline.splitlines(True), current.splitlines(True), fromfile="historical", tofile="current")), encoding="utf-8")
        write_json(diff_dir / "baseline_adjustments.json", {
            "removed_study_libname_statements": replacements,
            "reason": "Caller wrapper binds the same input library ACCESS=READONLY.",
            "original_sha256": sha256(ROOT / case["old_program"]),
        })
        for mode, source in [("baseline", baseline), ("current", current)]:
            if args.mode not in ("both", mode):
                continue
            case_dir = diff_dir / mode
            if (case_dir / "execution.json").exists():
                raise RuntimeError(f"Run already exists; choose a new batch: {case_dir}")
            (case_dir / "results").mkdir(parents=True, exist_ok=True)
            (case_dir / "program.sas").write_text(source, encoding="utf-8")
            wrapper = f'''options validmemname=extend;
libname study "{(ROOT / 'study/sas_data').as_posix()}" access=readonly;
libname results "{(case_dir / 'results').as_posix()}";
%put NOTE: [RUNTIME] SAS=&sysvlong4 platform=&sysscp;
proc options option=(encoding locale cardimage fmtsearch); run;
%include "program.sas";
%include "{(ROOT / 'test/fixtures/sas/runtime_v2/snapshot.sas').as_posix()}";
%put NOTE: [RUNTIME] complete;
'''
            (case_dir / "run.sas").write_text(wrapper, encoding="utf-8")
            result = run_sas(case_dir, timeout=240)
            outcomes.append({"case": case["case_id"], "mode": mode, **result})
            print(case["case_id"], mode, "exit", result["returncode"], "errors", len(result["errors"]), flush=True)
            write_json(batch / "executions.json", outcomes)
    after = {str(path.relative_to(ROOT)): sha256(path) for path in inputs}
    write_json(batch / "originals_unchanged.json", {"passed": before == after, "after": after})
    assert before == after
    if not all(c["process_checks_passed"] for c in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
