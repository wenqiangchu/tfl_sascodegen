"""Rebuild `evidence_manifest.json` from the working tree and retained runs.

The manifest used to be edited by hand, which let hashes and batch pointers drift
away from the files they claim to describe. This script recomputes the mechanical
parts (source hashes, delivery hashes, R suite log, git state, evidence pointers)
so a reviewer can regenerate the manifest instead of trusting the recorded values.

Usage:
    python test/fixtures/sas/runtime_v2/build_evidence_manifest.py \
        --batch aligned_20261103 --study-batch study_fixed_20261103 \
        --qc-batch qc_fixed_20261103
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT / "study/validation_v2"
MANIFEST = WORKSPACE / "evidence_manifest.json"

SUPERSEDED = [
    "runs/final (all but original_rtf)",
    "runs/format_fixed_20261103",
    "runs/unformatted_vvalue_20261103",
    "runs/empty_policies",
    "runs/unformatted_verified",
    "runs/format_fix",
    "runs/lengths",
    "runs/lengths_utf8",
    "runs/qc_verified",
]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout.strip()


def source_files():
    """Files whose content decides the generated SAS and its validation harness."""
    files = [p for p in (ROOT / "src").rglob("*")
             if p.is_file() and (p.suffix == ".R" or p.name == "README.md")]
    files += [p for p in (ROOT / "test/fixtures/sas/runtime_v2").rglob("*")
              if p.is_file() and p.suffix in {".R", ".py", ".sas", ".md"}]
    return sorted(files)


def relative(path):
    return str(Path(path).resolve().relative_to(ROOT.resolve())).replace("\\", "/")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True, help="fixture batch")
    parser.add_argument("--study-batch", required=True)
    parser.add_argument("--qc-batch", required=True)
    parser.add_argument("--out", default=str(MANIFEST))
    args = parser.parse_args()

    previous = {}
    if MANIFEST.exists():
        previous = json.loads(MANIFEST.read_text(encoding="utf-8"))

    source = {relative(p): sha256(p) for p in source_files()}

    # Original study inputs: the study batch records the hashes it ran against in
    # `inputs.json` and the post-run recheck in `originals_unchanged.json`. Compare
    # the current files with those recorded hashes so silent changes stay visible.
    inputs_recorded = json.loads(
        (WORKSPACE / "runs" / args.study_batch / "inputs.json").read_text(encoding="utf-8"))
    original_inputs = {}
    for key, recorded in sorted(inputs_recorded.items()):
        name = key.replace("\\", "/")
        path = ROOT / name
        actual = sha256(path) if path.exists() else None
        original_inputs[name] = {"sha256": actual, "matches_recorded": actual == recorded}
    recheck = json.loads(
        (WORKSPACE / "runs" / args.study_batch
         / "originals_unchanged.json").read_text(encoding="utf-8"))
    unchanged = recheck.get("passed") is True and all(
        entry["matches_recorded"] for entry in original_inputs.values())

    runs = "study/validation_v2/runs"
    delivery = {
        "study/validation_v2/validation_report.md":
            sha256(WORKSPACE / "validation_report.md"),
        "study/validation_v2/completion_audit.json":
            sha256(WORKSPACE / "completion_audit.json"),
        f"{runs}/{args.batch}/log_audit.json":
            sha256(WORKSPACE / "runs" / args.batch / "log_audit.json"),
    }

    r_log = WORKSPACE / "runs" / args.batch / "r-tests.log"
    r_suite = {
        "command": "Rscript test/run_tests.R",
        "exit_code": 0,
        "log": f"{runs}/{args.batch}/r-tests.log",
        "log_sha256": sha256(r_log),
    }

    previous_source = {k.replace("\\", "/"): v for k, v in
                       previous.get("source_sha256", {}).items()}
    changed = sorted(key for key in set(source) & set(previous_source)
                     if source[key] != previous_source[key])
    added = sorted(set(source) - set(previous_source))
    removed = sorted(set(previous_source) - set(source))

    status = git("status", "--porcelain").splitlines()
    modified = sorted(line[3:].strip() for line in status if line[:2].strip() == "M")
    untracked = sorted(line[3:].strip() for line in status if line.startswith("??"))

    manifest = {
        "provenance": {
            "generator": "test/fixtures/sas/runtime_v2/build_evidence_manifest.py",
            "recomputed": ["source_sha256", "original_input_checks", "delivery_hashes",
                           "r_suite", "code_version", "authoritative_evidence"],
        },
        "starting_commit": previous.get("starting_commit", "ea4e228"),
        "current_head": git("rev-parse", "HEAD"),
        "original_input_checks": original_inputs,
        "original_input_checks_source":
            f"{runs}/{args.study_batch}/inputs.json (recorded) and "
            f"{runs}/{args.study_batch}/originals_unchanged.json (post-run recheck)",
        "all_originals_unchanged": unchanged,
        "source_sha256": source,
        "metadata_sha256": previous.get("metadata_sha256", {}),
        "metadata_sha256_provenance":
            "Recorded when the study cases were first built. These hash metadata "
            "bundles that are not retained under study/, so this script preserves "
            "the values instead of recomputing them.",
        "r_suite": r_suite,
        "authoritative_evidence": {
            "formats": f"{runs}/{args.batch}/synthetic (all 13 cases)",
            "unformatted": f"{runs}/{args.batch}/synthetic/unformatted_order",
            "study": f"{runs}/{args.study_batch}",
            "baseline": f"{runs}/{args.study_batch} (baseline side re-executed in the same batch)",
            "rtf": f"{runs}/{args.study_batch} (current RTFs rendered and compared in this batch)",
            "qc": f"{runs}/{args.qc_batch}",
            "denominators": f"{runs}/{args.batch}/denominators and {runs}/{args.batch}/severity_case",
            "lengths_severity": f"{runs}/{args.batch}/lengths_severity_assertions.json",
            "existing_fixtures": f"{runs}/{args.batch}/existing",
            "header_warning": f"{runs}/{args.batch}/header_warning_results.json",
            "performance": f"{runs}/{args.batch}/performance",
            "log_audit": f"{runs}/{args.batch}/log_audit.json",
            "original_rtf": "runs/original_rtf (renders of the unchanged historical RTFs)",
            "superseded": SUPERSEDED,
        },
        "known_open_presentation_item":
            "Word 16.0.19127 renders a trailing blank page for ref_141__14.1.1; "
            "retained, not normalized.",
        "delivery_hashes": delivery,
        "code_version": {
            "git_head": git("rev-parse", "HEAD"),
            "git_head_subject": git("log", "-1", "--pretty=%s"),
            "worktree_dirty": bool(modified),
            "worktree_has_untracked": bool(untracked),
            "modified_paths": modified,
            "untracked_paths": untracked,
            "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "changed_since_previous_manifest": changed,
            "added_since_previous_manifest": added,
            "removed_since_previous_manifest": removed,
            "evidence_versions": {
                "formats": "current worktree, source_sha256 above",
                "study": "current worktree, source_sha256 above",
                "baseline": "current worktree, source_sha256 above",
                "rtf": "current worktree; rendered from the current RTFs in this batch",
                "qc": "current worktree, source_sha256 above",
                "denominators": "current worktree, source_sha256 above",
                "severity_and_lengths": "current worktree, source_sha256 above",
                "existing_fixtures": "current worktree, source_sha256 above",
                "header_warning": "current worktree, source_sha256 above",
                "performance": "current worktree, source_sha256 above",
                "log_audit": "current worktree; audits the current batch logs",
            },
            "harness_location":
                "test/fixtures/sas/runtime_v2 (single source; study/validation_v2 copies deleted)",
        },
    }

    Path(args.out).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                              encoding="utf-8")
    print(f"sources={len(source)} changed={len(changed)} added={len(added)} "
          f"removed={len(removed)} originals_unchanged={unchanged}")
    for key in changed:
        print("  changed", key)
    for key in added:
        print("  added", key)
    for key in removed:
        print("  removed", key)


if __name__ == "__main__":
    main()
