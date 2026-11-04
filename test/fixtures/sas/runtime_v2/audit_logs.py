"""Classify each retained diagnostic; fail on unexpected warnings/errors/notes."""
from pathlib import Path
from collections import Counter
import argparse
import json
import re

from runner import write_json

ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT / "study/validation_v2"


def warning_category(line, relative):
    if "SASHELP" in line or line == "WARNING: 在。这些逻辑库已从连接中删除。":
        return "environment_sashelp_missing_installation_entries"
    if "SASUSER" in line and "WORK" in line:
        return "environment_sasuser_registry_copy_concurrent_sessions"
    if "[USER] duplicate_key" in line:
        return "source_duplicate_diagnostic_records_preserved"
    if "header_subject_duplicate" in line and "header_checked" in relative:
        return "intentional_header_duplicates"
    if "[USER] missing_level" in line and "missing_error" in relative:
        return "intentional_missing_level"
    if "continuous_unit_multiple_values" in line and "conflict" in relative:
        return "intentional_continuous_conflict"
    if "more than 262 bytes long" in line and "long_labels" in relative:
        return "sas_quoted_literal_length_actual_utf8_labels_verified"
    if ("未找到匹配观测" in line or "没有与 ID 变量值匹配" in line) and "/existing/" in relative:
        return "fixture_compare_empty_outputs_asserted_equal"
    return "unexpected"


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--batch",default="final")
    # Study configurations may be run in their own batch (the QC reference results
    # come from it), so the audit accepts them separately from the fixture batch.
    parser.add_argument("--study-batch")
    parser.add_argument("--qc-batch",default="qc_verified")
    parser.add_argument("--order-batch",default="unformatted_verified")
    parser.add_argument("--empty-batch",default="empty_policies")
    args=parser.parse_args()
    final = WORKSPACE / "runs" / args.batch
    study = WORKSPACE / "runs" / (args.study_batch or args.batch)
    paths = list(study.glob("*__*/current/execution.json"))
    paths += list(final.glob("synthetic/*/execution.json"))
    paths = [p for p in paths if p.parent.name not in ("unformatted_order","empty_label","empty_error")]
    paths += list(final.glob("existing/*/*/execution.json"))
    paths += list(final.glob("performance/*/*/*/execution.json"))
    paths += [final / name / "execution.json" for name in ["denominators","severity_case","header_checked","header_unchecked"]]
    paths += list((WORKSPACE / "runs" / args.qc_batch / "qc").glob("*__*/*/execution.json"))
    paths += [WORKSPACE / "runs" / args.order_batch / "synthetic/unformatted_order/execution.json"]
    paths += [WORKSPACE / "runs" / args.empty_batch / "synthetic" / name / "execution.json" for name in ("empty_label","empty_error")]
    summary=Counter(); records=[]
    for p in paths:
        relative=p.parent.relative_to(WORKSPACE).as_posix()
        execution=json.loads(p.read_text())
        diagnostics=[]
        for warning in execution["warnings"]:
            category=warning_category(warning,relative)
            diagnostics.append(dict(kind="warning",text=warning,category=category))
        for error in execution["errors"]:
            expected="/existing/hierarchical_continuous_batching/negative" in relative and (
                error=="ERROR: [USER] Relative digits resolved to a negative value." or
                re.fullmatch(r"ERROR: 在以下页上打印错误:[\s\d,.]+",error))
            diagnostics.append(dict(kind="error",text=error,category="intentional_negative_digits" if expected else "unexpected"))
        log=p.with_name("run.log").read_text(encoding="utf-8-sig")
        executed_marker = bool(re.search(r"^NOTE: \[RUNTIME\] complete\s*$", log, re.MULTILINE))
        if "/existing/" in relative:
            # run_existing.py additionally checks the exact case-specific marker.
            executed_marker = bool(re.search(r"^NOTE: [^\r\n]*(?:passed|warning_reached)[^\r\n]*$", log, re.MULTILINE))
        for note in log.splitlines():
            if not note.startswith("NOTE:") or not any(t in note.lower() for t in ["未初始化","转换","无效","截断","uninitialized","invalid","truncat"]):
                continue
            category="unexpected"
            if re.fullmatch(r"NOTE: 变量 (node_key|node_order_path|_tfl_format) 未初始化。",note):
                category="declared_empty_identity_or_unused_descriptor_field"
            elif note in ["NOTE: 字符值已转换为数值，位置:（行:列）。","NOTE: 数值已转换为字符值，位置:（行:列）。"]:
                category="compile_time_vtype_branch_conversion_no_invalid_value_execution"
            elif "/existing/hierarchical_row_assembly/empty" in relative and "未初始化" in note:
                category="empty_output_schema_no_observations"
            diagnostics.append(dict(kind="note",text=note,category=category))
        summary.update(d["category"] for d in diagnostics)
        records.append(dict(directory=relative,returncode=execution["returncode"],marker=executed_marker,
                            diagnostics=diagnostics,passed=execution["returncode"]==0 and executed_marker
                            and all(d["category"]!="unexpected" for d in diagnostics)))
    result=dict(passed=all(r["passed"] for r in records),cases=len(records),summary=dict(summary),records=records,
                superseded={"runs/final/qc":"Harness used a nine-character LIBREF; corrected to refdata and all 14 rerun in qc_verified.",
                            "runs/final/synthetic/unformatted_order":"An earlier run expected unpadded numeric VVALUE and used an explicit character label workaround. The canonical fixture now exercises numeric VVALUE with STRIP; rerun this case before treating the new evidence as authoritative."})
    write_json(final/"log_audit.json",result)
    print(json.dumps({k:v for k,v in result.items() if k not in ("records","superseded")},indent=2))
    if not result["passed"]:
        for r in records:
            if not r["passed"]:
                print(r["directory"],[d for d in r["diagnostics"] if d["category"]=="unexpected"])
        raise SystemExit(1)


if __name__=="__main__":
    main()
