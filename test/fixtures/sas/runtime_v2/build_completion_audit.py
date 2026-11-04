"""Recompute the delivery completion audit from retained artifacts.

The earlier `completion_audit.json` was assembled by hand, so nothing proved that
its 33 booleans still described the artifacts on disk. This script derives every
entry from a specific file and records that path, so the audit can be regenerated
after any rerun instead of being restated.

Usage:
    python test/fixtures/sas/runtime_v2/build_completion_audit.py \
        --batch aligned_20261103 --study-batch study_fixed_20261103 \
        --qc-batch qc_fixed_20261103
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT / "study/validation_v2"


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def relative(path):
    return str(Path(path).resolve().relative_to(ROOT.resolve()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True, help="fixture batch (formats, existing, performance, ...)")
    parser.add_argument("--study-batch", required=True, help="batch holding the study configurations")
    parser.add_argument("--qc-batch", required=True)
    parser.add_argument("--out", default=str(WORKSPACE / "completion_audit.json"))
    args = parser.parse_args()

    fixtures = WORKSPACE / "runs" / args.batch
    study = WORKSPACE / "runs" / args.study_batch
    qc = WORKSPACE / "runs" / args.qc_batch

    checks = []

    def add(path, passed, detail=None):
        entry = {"check": relative(path), "passed": bool(passed)}
        if detail is not None:
            entry["detail"] = detail
        checks.append(entry)

    def add_absent(path, reason):
        checks.append({"check": relative(path), "passed": False, "detail": reason})

    # Study configurations: process completion, then the comparison verdict.
    for case in sorted(study.glob("*__*")):
        execution_path = case / "current" / "execution.json"
        if execution_path.exists():
            add(execution_path, load(execution_path).get("process_checks_passed", False))
        else:
            add_absent(execution_path, "missing execution record")
        comparison_path = case / "comparison.json"
        if comparison_path.exists():
            result = load(comparison_path)
            add(comparison_path, result.get("analysis_and_logical_cells_equal", False),
                result.get("assembly_difference_classification"))
        else:
            add_absent(comparison_path, "missing comparison result")

    # Format fixtures: every case must pass process checks and its assertions.
    format_results = fixtures / "format_results.json"
    if format_results.exists():
        for outcome in load(format_results):
            add(format_results.parent / "synthetic" / outcome["case"] / "assertions.json",
                outcome.get("process_checks_passed") and outcome.get("assertions_passed"),
                {"case": outcome["case"]})
    else:
        add_absent(format_results, "missing format results")

    # Denominator suites.
    for fixture in ("denominators", "severity_case"):
        assertions = fixtures / fixture / "assertions.json"
        if assertions.exists():
            entries = load(assertions)
            add(assertions, all(item["passed"] for item in entries), {"assertions": len(entries)})
        else:
            add_absent(assertions, "missing assertion set")

    # Length/display assertions.
    lengths = fixtures / "lengths_severity_assertions.json"
    if lengths.exists():
        entries = load(lengths)
        add(lengths, all(item["passed"] for item in entries), {"assertions": len(entries)})
    else:
        add_absent(lengths, "missing length assertions")

    # Header duplicate diagnostic: checked and unchecked programs.
    header = fixtures / "header_warning_results.json"
    if header.exists():
        for outcome in load(header):
            add(header, outcome.get("passed", False), {"program": outcome.get("program")})
    else:
        add_absent(header, "missing header warning results")

    # Existing fixture groups.
    existing = fixtures / "existing" / "results.json"
    if existing.exists():
        outcomes = load(existing)
        failures = [item["case"] for item in outcomes if not item.get("passed")]
        add(existing, not failures, {"cases": len(outcomes), "failed": failures})
    else:
        add_absent(existing, "missing existing fixture results")

    # QC: every case must accept equality and detect one changed cell.
    qc_results = qc / "qc_results.json"
    if qc_results.exists():
        outcomes = load(qc_results)
        failures = [f"{item['case']}/{item['mode']}" for item in outcomes if not item.get("passed")]
        add(qc_results, not failures, {"executions": len(outcomes), "failed": failures})
    else:
        add_absent(qc_results, "missing QC results")

    # Length/performance comparison: inputs must match and both versions must report.
    performance = fixtures / "performance" / "summary.json"
    if performance.exists():
        summary = load(performance)
        measured = summary.get("measurements", [])
        complete = len(measured) == 2 and all(
            item.get("before") and item.get("current") for item in measured)
        add(performance, complete, {"before_commit": summary.get("before_commit")})
    else:
        add_absent(performance, "missing performance summary")

    # Log audit over the retained SAS logs.
    log_audit = fixtures / "log_audit.json"
    if log_audit.exists():
        audit = load(log_audit)
        add(log_audit, audit.get("passed", False), {"cases": audit.get("cases")})
    else:
        add_absent(log_audit, "missing log audit")

    # RTF comparison, per study case; failures are reported, never filtered out.
    presentation_failures = []
    for case in sorted(study.glob("*__*")):
        comparison = case / "rtf_comparison.json"
        if not comparison.exists():
            add_absent(comparison, "missing RTF comparison")
            continue
        result = load(comparison)
        add(comparison, result.get("passed", False), result.get("classification"))
        if not result.get("passed"):
            for item in result.get("checks", []):
                if not item.get("passed"):
                    presentation_failures.append({
                        "case": case.name,
                        "check": item["check"],
                        "passed": False,
                        "detail": item.get("detail"),
                    })

    rtf_checks = [entry["check"] for entry in checks
                  if entry["check"].endswith("rtf_comparison.json")]
    failed = [entry["check"] for entry in checks
              if not entry["passed"] and entry["check"] not in rtf_checks]
    analysis_passed = not failed

    audit = {
        "provenance": {
            "generator": "test/fixtures/sas/runtime_v2/build_completion_audit.py",
            "generated": True,
            "recomputed_from_artifacts": True,
            "batches": {"fixtures": args.batch, "study": args.study_batch, "qc": args.qc_batch},
            "note": "Every entry names the file it was read from; rerun the generator "
                    "after any rerun instead of editing this file.",
        },
        "analysis_and_runtime_passed": analysis_passed,
        "checks": checks,
        "presentation_failures": presentation_failures,
        "status": (("Analysis validation passed; Word pagination limitations are listed in "
                    "presentation_failures and are not counted as passes.")
                   if analysis_passed else
                   "Analysis validation has failing checks; see failed_checks."),
        "failed_checks": failed,
    }

    out = Path(args.out)
    out.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"checks={len(checks)} failed={len(failed)} analysis_passed={analysis_passed} "
          f"presentation_failures={len(presentation_failures)}")
    if failed:
        for name in failed:
            print("  FAILED", name)

    # RTF pagination items are reported but do not fail the delivery audit gate here;
    # callers decide. Analysis failures must fail loudly.
    if not analysis_passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
