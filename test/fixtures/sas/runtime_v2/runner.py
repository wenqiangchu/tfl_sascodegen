"""Run external SAS cases with isolated output, timeout, and retained evidence."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_sas(case_dir: Path, program: str = "run.sas", *, timeout: int = 180,
            sysparm: str | None = None, expected_errors: int = 0,
            marker: str = "[RUNTIME] complete") -> dict:
    case_dir = case_dir.resolve()
    sas = os.environ.get("TFL_SAS_EXECUTABLE", r"E:\sas\SASFoundation\9.4\sas.exe")
    command = [sas, "-sysin", program, "-log", "run.log", "-print", "run.lst",
               "-nosplash", "-noterminal"]
    if sysparm is not None:
        command += ["-sysparm", sysparm]
    started = time.time()
    try:
        process = subprocess.run(command, cwd=case_dir, timeout=timeout, capture_output=True,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        returncode = process.returncode
        timed_out = False
    except subprocess.TimeoutExpired:
        returncode, timed_out = None, True
    log_path = case_dir / "run.log"
    log = log_path.read_text(encoding="utf-8-sig", errors="replace") if log_path.exists() else ""
    errors = re.findall(r"^ERROR[^\r\n]*", log, re.MULTILINE)
    warnings = re.findall(r"^WARNING[^\r\n]*", log, re.MULTILINE)
    # Require an executed diagnostic, not a matching %PUT in echoed source.
    marker_found = re.search(r"^NOTE: [^\r\n]*" + re.escape(marker) + r"[^\r\n]*$", log, re.MULTILINE) is not None
    record = {
        "command": command, "working_directory": str(case_dir), "started_unix": started,
        "elapsed_seconds": time.time() - started, "timeout_seconds": timeout,
        "timed_out": timed_out, "returncode": returncode,
        "program_sha256": sha256(case_dir / program),
        "log_sha256": sha256(log_path) if log_path.exists() else None,
        "errors": errors, "warnings": warnings, "expected_marker": marker, "marker_found": marker_found,
        "process_checks_passed": not timed_out and returncode == 0
        and len(errors) == expected_errors and marker_found,
    }
    write_json(case_dir / "execution.json", record)
    return record
