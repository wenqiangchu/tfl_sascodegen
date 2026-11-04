"""Rebuild existing synthetic fixtures in a source snapshot, then run fresh copies."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess

from runner import run_sas, sha256, write_json

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    destination = ROOT / "study/validation_v2/runs" / args.batch / "existing"
    context = destination / "build_context"
    if context.exists() and not args.verify_only:
        raise RuntimeError("Choose a new batch; the build context already exists.")
    if not args.verify_only:
        shutil.copytree(ROOT / "src", context / "src")
    source_hashes = {str(p.relative_to(context)): sha256(p) for p in (context / "src").rglob("*.R")}
    write_json(context / "source_hashes.json", source_hashes)
    cases = {
        "continuous_counting_units": [
            ("record", "run_record.sas", None, "record counting unit passed", 0, 0),
            ("distinct_subject", "run_distinct_subject.sas", None, "distinct_subject counting unit passed", 0, 0),
            ("distinct_key", "run_distinct_key.sas", None, "typed distinct_key counting unit passed", 0, 0),
            ("shared_level", "run_shared_level.sas", None, "shared anchor-level membership expansion passed", 0, 0),
            ("conflict", "run_distinct_subject_conflict.sas", None, "fixture_expected_warning_reached", 0, 1),
        ],
        "hierarchical_continuous_batching": [
            (case, "run_success.sas", case, f"shared continuous {case} passed", 24 if case == "negative" else 0, 0)
            for case in ["record", "four", "varied", "negative", "subject", "key", "empty", "missing"]
        ] + [(case, "run_conflict.sas", case, "expected_second_block_warning_reached", 0, 2)
             for case in ["subject_conflict", "key_conflict"]],
        "hierarchical_row_assembly": [
            (case, "run_case.sas", case, f"row assembly {case} passed", 0, 0)
            for case in ["basic", "sorted", "multilevel", "mixed", "empty"]
        ],
    }
    outcomes = []
    for group, specifications in cases.items():
        fixture = context / "test/fixtures/sas" / group
        if not args.verify_only:
            fixture.mkdir(parents=True)
            for path in (ROOT / "test/fixtures/sas" / group).iterdir():
                if path.suffix in (".R", ".sas") and path.is_file():
                    shutil.copy2(path, fixture / path.name)
            built = subprocess.run(["Rscript", str(fixture / "build_sources.R")], cwd=context,
                                   capture_output=True, text=True, encoding="utf-8", errors="replace")
            (fixture / "build.log").write_text(built.stdout + built.stderr, encoding="utf-8")
            if built.returncode:
                raise RuntimeError(f"Fixture builder failed: {group}")
        for case, program, sysparm, marker, errors, conflicts in specifications:
            output = destination / group / case
            if args.verify_only:
                execution = json.loads((output / "execution.json").read_text(encoding="utf-8"))
            else:
                shutil.copytree(fixture, output)
                execution = run_sas(output, program, sysparm=sysparm, expected_errors=errors, marker=marker)
            conflict_count = sum("continuous_unit_multiple_values" in value for value in execution["warnings"])
            log = (output / "run.log").read_text(encoding="utf-8-sig")
            diagnostics = execution["errors"]
            negative_paths_passed = True
            summaries = []
            if case == "negative":
                # SAS appends an error-page summary after the intentional diagnostics.
                summaries = [v for v in diagnostics if re.fullmatch(
                    r"ERROR: (?:在以下页上打印错误:|Errors printed on pages)[\s\d,\.]+", v)]
                diagnostics = [v for v in diagnostics if v not in summaries]
                independent, shared = re.split(r"(?m)^NOTE: \[FIXTURE\] begin shared negative\s*$", log, maxsplit=1)
                pattern = r"^ERROR: \[USER\] Relative digits resolved to a negative value\.$"
                negative_paths_passed = len(re.findall(pattern, independent, re.M)) == 12 and len(re.findall(pattern, shared, re.M)) == 12
            expected_error_text = all(value == "ERROR: [USER] Relative digits resolved to a negative value." for value in diagnostics)
            marker_found = re.search(r"^NOTE: [^\r\n]*" + re.escape(marker), log, re.MULTILINE) is not None
            process_passed = not execution["timed_out"] and execution["returncode"] == 0 and marker_found
            outcome = {"group": group, "case": case,
                       "passed": process_passed and len(diagnostics) == errors and conflict_count == conflicts
                       and expected_error_text and negative_paths_passed,
                       "conflict_warning_count": conflict_count, "expected_conflict_warning_count": conflicts,
                       "diagnostic_error_count": len(diagnostics), "error_page_summaries": summaries}
            outcomes.append(outcome)
            print(outcome, flush=True)
            write_json(destination / "results.json", outcomes)
    if not all(c["passed"] for c in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
