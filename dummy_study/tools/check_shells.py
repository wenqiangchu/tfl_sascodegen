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

import yaml
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


def declared_label_texts(text):
    """The label texts a shell lists in its §3 label rows.

    A §3 table row that names `label` as its row type carries the visible label in
    the third column, so the text itself is available. Comparing texts rather than
    counting rows is what catches a renamed label: the count is unchanged, so a
    count-only check would pass.
    """
    texts = []
    for line in text.splitlines():
        if not is_label_row(line):
            continue
        cells = [cell.strip().strip("*").strip() for cell in line.strip().strip("|").split("|")]
        # Every §3 table puts the row label immediately after the index column,
        # whatever the remaining columns are.
        if len(cells) >= 2:
            texts.append(cells[1])
    return texts


def template_label_texts(path):
    """The `type: label` row labels a template emits, parsed rather than grepped."""
    document = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    texts = []

    def walk(value):
        if isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, dict):
            if value.get("type") == "label" and "label" in value:
                texts.append(str(value["label"]))
            for item in value.values():
                walk(item)

    walk(document)
    return texts


def check_section_labels(name, text):
    """Compare the shell's declared label rows with the template's emitted ones."""
    match = TABLE_NUMBER.match(name)
    if not match:
        return []
    number = match.group(1).replace(".", "_")
    candidates = sorted(TABLES.glob(f"t_{number}_*.yaml"))
    if len(candidates) != 1:
        return [f"{name}: expected one table file for {number}, found {len(candidates)}"]
    table_document = yaml.safe_load(candidates[0].read_text(encoding="utf-8")) or {}
    template_id = table_document.get("template_id")
    if not template_id:
        return [f"{name}: {candidates[0].name} has no template_id"]
    template_path = TEMPLATES / f"{template_id}.yaml"
    if not template_path.exists():
        return [f"{name}: missing template {template_path.name}"]

    declared = declared_label_texts(text)
    emitted = template_label_texts(template_path)
    if len(declared) != len(emitted):
        return [f"{name}: §3 declares {len(declared)} section label row(s) but "
                f"{template_path.name} emits {len(emitted)}"]
    if sorted(declared) != sorted(emitted):
        missing = sorted(set(emitted) - set(declared))
        extra = sorted(set(declared) - set(emitted))
        return [f"{name}: §3 label texts differ from {template_path.name} "
                f"(missing: {missing}, extra: {extra})"]
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
