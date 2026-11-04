"""Verify Header uniqueness warnings, including subjects excluded by population."""
from pathlib import Path
import argparse
import re
import shutil

from runner import run_sas, write_json

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    args = parser.parse_args()
    outcomes = []
    for mode in ["checked", "unchecked"]:
        output = ROOT / "study/validation_v2/runs" / args.batch / ("header_" + mode)
        output.mkdir(parents=True, exist_ok=False)
        shutil.copy2(ROOT / "study/validation_v2/denominators" / f"header_{mode}.sas", output / "program.sas")
        (output / "run.sas").write_text('''options nosource nosource2;
%include "program.sas";
proc sql noprint;
  select count(*) into :raw_count trimmed from work.rv_adsl;
  select count(*) into :population_count trimmed from work._TFL_POP_001;
quit;
%put NOTE: [HEADER] raw=&raw_count population=&population_count;
%put NOTE: [RUNTIME] complete;
''', encoding="utf-8")
        execution = run_sas(output)
        log = (output / "run.log").read_text(encoding="utf-8-sig")
        warnings = [v for v in execution["warnings"] if "header_subject_duplicate" in v]
        expected_count = 2 if mode == "checked" else 0
        checks = {"process": execution["process_checks_passed"],
                  "warning_count": len(warnings) == expected_count,
                  "records_unchanged": "NOTE: [HEADER] raw=6 population=4" in log,
                  "both_source_subjects_checked": mode == "unchecked" or
                  sorted(re.search(r"USUBJID=(\d+)", v).group(1) for v in warnings) == ["01", "99"]}
        outcome = {"mode": mode, "checks": checks, "passed": all(checks.values()), "warnings": warnings}
        outcomes.append(outcome)
        print(mode, outcome["passed"], flush=True)
    write_json(ROOT / "study/validation_v2/runs" / args.batch / "header_warning_results.json", outcomes)
    if not all(c["passed"] for c in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
