"""Verify generated QC programs accept equality and detect one changed cell."""
from pathlib import Path
import argparse
import json
import re
import shutil

from runner import run_sas, write_json

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--report-batch", required=True)
    args = parser.parse_args()
    workspace = ROOT / "study/validation_v2"
    outcomes = []
    for case in json.loads((workspace / "cases.json").read_text()):
        for mode in ("equal", "changed"):
            output = workspace / "runs" / args.batch / "qc" / case["case_id"] / mode
            (output / "tables").mkdir(parents=True, exist_ok=False)
            shutil.copy2(workspace / "generated" / case["case_id"] / "compare.sas", output / "program.sas")
            reference = workspace / "runs" / args.report_batch / case["case_id"] / "current/results"
            mutation = "" if mode == "equal" else """
  retain changed 0;
  if not changed and not missing(col_001) then do;
    col_001='INTENTIONAL_QC_DIFFERENCE'; changed=1;
    putlog 'NOTE: [QC] changed exactly one cell';
  end;
  drop changed;
"""
            (output / "run.sas").write_text(f'''options validmemname=extend nosource nosource2;
libname study "{(ROOT / 'study/sas_data').as_posix()}" access=readonly;
libname refdata "{reference.as_posix()}" access=readonly;
libname tables "{(output / 'tables').as_posix()}";
data tables.'{case['table_id']}'n;
  set refdata._TFL_ASM_001;
{mutation}
run;
%include "program.sas";
%let rv_compare_status=&sysinfo;
%put NOTE: [QC] SYSINFO=&rv_compare_status;
%put NOTE: [RUNTIME] complete;
''', encoding="utf-8")
            execution = run_sas(output, timeout=240)
            log = (output / "run.log").read_text(encoding="utf-8-sig")
            match = re.search(r"NOTE: \[QC\] SYSINFO=(\d+)", log)
            status = int(match[1]) if match else None
            checks = {"process": execution["process_checks_passed"],
                      "sysinfo": status == (0 if mode == "equal" else 4096),
                      "changed_cell_count": log.count("NOTE: [QC] changed exactly one cell") == int(mode == "changed")}
            result = dict(case=case["case_id"], mode=mode, sysinfo=status, checks=checks, passed=all(checks.values()))
            outcomes.append(result)
            write_json(output / "assertions.json", result)
            write_json(workspace / "runs" / args.batch / "qc_results.json", outcomes)
            print(result, flush=True)
    if not all(item["passed"] for item in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
