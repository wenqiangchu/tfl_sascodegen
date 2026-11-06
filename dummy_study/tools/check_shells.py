"""Check the dummy study shells against the data descriptors.

The shells are hand-written specification documents, so they can drift away from
the datasets: a renamed variable, a typo in a domain prefix, or a length that was
written from memory. This script re-derives the facts it can check and fails
loudly instead of letting the drift reach the metadata bundle.

Checks:
  1. every shell has the six template sections;
  2. every `DOMAIN.VARIABLE` reference names a variable that exists in that dataset;
  3. every declared `char(N)` length matches the SAS length in descriptors.csv;
  4. no shell uses the literal string "nan" as a value;
  5. the section-label rows a shell declares in §3 are the ones the metadata
     template actually emits.

Check 5 exists because the first draft of the bundle dropped every section
heading: the statistics still matched, so no numeric check noticed that
"Age (years)" had stopped being printed as its own row.

`WORK.*` references name datasets the shell derives in `custom_code.before`, so they
are out of scope for the descriptor check; they are documented in each shell's
variable dictionary under "派生".

Run from anywhere:
    python dummy_study/tools/check_shells.py
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELLS = ROOT / "shell"
DESCRIPTORS = ROOT / "variables" / "descriptors.csv"
TABLES = ROOT / "metadata" / "tables"
TEMPLATES = ROOT / "metadata" / "templates"

SECTIONS = ("## 1. Identity", "## 2. Columns", "## 3. Rows",
            "## 4. Variable dictionary", "## 5. Chunk plan", "## 6. Open points")

# Datasets the shells build themselves; they have no descriptor rows.
DERIVED_DOMAINS = {"WORK"}

REFERENCE = re.compile(r"`([A-Z]+)\.([A-Z0-9_]+)`")
DECLARATION = re.compile(r"^\|\s*`[A-Z]+\.[A-Z0-9_]+`\s*\|.*?\|\s*(char|num)(?:\((\d+)\))?\s*\|")
DECLARED_VAR = re.compile(r"^\|\s*`([A-Z]+)\.([A-Z0-9_]+)`\s*\|")
TABLE_NUMBER = re.compile(r"^(\d+(?:\.\d+)+)")
# A section-label row is a numbered table row with a cell reading "label";
# splitting on the pipes keeps this independent of how many columns a shell uses.
def is_label_row(line):
    if not line.startswith("|"):
        return False
    cells = [cell.strip().strip("*").strip() for cell in line.strip().strip("|").split("|")]
    if not cells or not cells[0].isdigit():
        return False
    return "label" in (cell.lower() for cell in cells)
TEMPLATE_ID = re.compile(r"^template_id:\s*'([^']+)'", re.M)
LABEL_ROW_ID = re.compile(r"^\s*-\s*id:")
LABEL_ROW_TYPE = re.compile(r"^\s*type:\s*'label'")


def count_template_label_rows(path):
    """Count the `type: 'label'` rows in a template, which sit under their id."""
    lines = path.read_text(encoding="utf-8").splitlines()
    count = 0
    for previous, current in zip(lines, lines[1:]):
        if LABEL_ROW_ID.match(previous) and LABEL_ROW_TYPE.match(current):
            count += 1
    return count


def check_section_labels(name, text):
    """Compare the shell's declared label rows with the template's emitted ones."""
    match = TABLE_NUMBER.match(name)
    if not match:
        return []
    number = match.group(1).replace(".", "_")
    candidates = sorted(TABLES.glob(f"t_{number}_*.yaml"))
    if len(candidates) != 1:
        return [f"{name}: expected one table file for {number}, found {len(candidates)}"]
    table_text = candidates[0].read_text(encoding="utf-8")
    template_match = TEMPLATE_ID.search(table_text)
    if not template_match:
        return [f"{name}: {candidates[0].name} has no template_id"]
    template_path = TEMPLATES / f"{template_match.group(1)}.yaml"
    if not template_path.exists():
        return [f"{name}: missing template {template_path.name}"]

    declared = sum(1 for line in text.splitlines() if is_label_row(line))
    emitted = count_template_label_rows(template_path)
    if declared != emitted:
        return [f"{name}: §3 declares {declared} section label row(s) but "
                f"{template_path.name} emits {emitted}"]
    return []


def load_descriptors():
    table = {}
    with DESCRIPTORS.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            table[(row["domain"].upper(), row["NAME"])] = row
    return table


def main():
    if not DESCRIPTORS.exists():
        raise SystemExit(f"Missing descriptors: {DESCRIPTORS}")
    descriptors = load_descriptors()
    problems = []
    files = sorted(SHELLS.glob("*.md"))
    if not files:
        raise SystemExit(f"No shells found under {SHELLS}")

    for path in files:
        name = path.name
        lines = path.read_text(encoding="utf-8").splitlines()
        text = "\n".join(lines)

        for section in SECTIONS:
            if section not in text:
                problems.append(f"{name}: missing section '{section}'")

        if "`nan`" in text:
            problems.append(f"{name}: literal 'nan' used as a value")

        problems.extend(check_section_labels(name, text))

        # 2. every referenced DOMAIN.VARIABLE must exist
        for domain, variable in sorted(set(REFERENCE.findall(text))):
            if domain in DERIVED_DOMAINS:
                continue
            if (domain, variable) not in descriptors:
                problems.append(f"{name}: references unknown variable {domain}.{variable}")

        # 3. declared lengths in the variable dictionary must match SAS
        for line in lines:
            kind_match = DECLARATION.match(line)
            var_match = DECLARED_VAR.match(line)
            if not kind_match or not var_match:
                continue
            domain, variable = var_match.group(1), var_match.group(2)
            descriptor = descriptors.get((domain, variable))
            if descriptor is None:
                continue  # already reported by check 2
            kind, length = kind_match.group(1), kind_match.group(2)
            actual_kind = "char" if descriptor["TYPE"] == "2" else "num"
            if kind != actual_kind:
                problems.append(f"{name}: {domain}.{variable} declared {kind}, data is {actual_kind}")
            elif kind == "char" and length and int(length) != int(descriptor["LENGTH"]):
                problems.append(
                    f"{name}: {domain}.{variable} declared char({length}), "
                    f"data is char({descriptor['LENGTH']})")

    print(f"checked {len(files)} shells against {len(descriptors)} descriptors")
    if problems:
        print(f"{len(problems)} problem(s):")
        for problem in problems:
            print("  -", problem)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
