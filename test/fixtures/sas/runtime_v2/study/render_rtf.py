"""Read-only Word rendering and structured layout capture for isolated RTF copies."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "test/fixtures/sas/runtime_v2"))
from runner import sha256, write_json

NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "pkg": "http://schemas.microsoft.com/office/2006/xmlPackage"}


def attributes(element):
    return {} if element is None else {key.split("}")[-1]: value for key, value in element.attrib.items()}


def render_one(source, output):
    import win32com.client
    output.mkdir(parents=True, exist_ok=True)
    original_hash = sha256(source)
    word = win32com.client.DispatchEx("Word.Application")
    document = None
    try:
        word.Visible = False
        word.DisplayAlerts = 0
        word.AutomationSecurity = 3
        write_json(output / "renderer.json", {"application": "Microsoft Word", "version": word.Version,
                                             "build": word.Build, "source_sha256": original_hash})
        document = word.Documents.Open(str(source), False, True, False)
        document.Repaginate()
        document.ExportAsFixedFormat(str(output / "report.pdf"), 17, False)
        xml = document.WordOpenXML
        (output / "document.xml").write_text(xml, encoding="utf-8")
        root = ET.fromstring(xml)
        body = next(part for part in root.findall("pkg:part", NS)
                    if part.get("{" + NS["pkg"] + "}name") == "/word/document.xml")
        tables = []
        for table in body.findall(".//w:tbl", NS):
            rows = []
            for row in table.findall("w:tr", NS):
                cells = []
                for cell in row.findall("w:tc", NS):
                    paragraphs = [{"text": "".join(t.text or "" for t in p.findall(".//w:t", NS)),
                                   "indent": attributes(p.find("w:pPr/w:ind", NS)),
                                   "alignment": attributes(p.find("w:pPr/w:jc", NS))}
                                  for p in cell.findall("w:p", NS)]
                    cells.append({"paragraphs": paragraphs,
                                  "width": attributes(cell.find("w:tcPr/w:tcW", NS)),
                                  "span": attributes(cell.find("w:tcPr/w:gridSpan", NS))})
                rows.append({"header": row.find("w:trPr/w:tblHeader", NS) is not None, "cells": cells})
            tables.append({"grid": [attributes(c) for c in table.findall("w:tblGrid/w:gridCol", NS)], "rows": rows})
        layout = {"pages": document.ComputeStatistics(2), "tables": tables,
                  "sections": [{"size": attributes(s.find("w:pgSz", NS)),
                                "margins": attributes(s.find("w:pgMar", NS))}
                               for s in body.findall(".//w:sectPr", NS)]}
        write_json(output / "layout.json", layout)
    finally:
        if document is not None:
            document.Close(False)
        word.Quit()
    assert sha256(source) == original_hash
    subprocess.run(["pdftoppm", "-r", "65", "-png", str(output / "report.pdf"), str(output / "page")],
                   check=True, capture_output=True, timeout=90,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def discard_stale_render(output):
    # Page images are globbed when the layout is compared, so a leftover page-4.png
    # from a longer earlier render would survive into the new capture.
    for name in ("layout.json", "renderer.json", "report.pdf", "document.xml"):
        (output / name).unlink(missing_ok=True)
    for page in output.glob("page-*.png"):
        page.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.source:
        render_one(args.source.resolve(), args.output.resolve())
        return
    batch = ROOT / "study/validation_v2/runs" / args.batch
    outcomes = []
    for source in sorted(batch.glob("*__*/[bc]*/*.rtf")):
        output = source.parent / "visual"
        renderer_path = output / "renderer.json"
        try:
            prior_renderer = json.loads(renderer_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            prior_renderer = {}
        current_hash = sha256(source)
        if (prior_renderer.get("source_sha256") == current_hash
                and (output / "layout.json").exists()
                and (output / "report.pdf").exists()
                and list(output.glob("page-*.png"))):
            continue
        if output.exists():
            discard_stale_render(output)
            print("cache_stale", source.parent.name, source.name, flush=True)
        command = [sys.executable, str(Path(__file__).resolve()), "--source", str(source), "--output", str(output)]
        try:
            process = subprocess.run(command, capture_output=True, timeout=150, text=True,
                                     encoding="utf-8", errors="replace",
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            result = {"source": str(source), "returncode": process.returncode,
                      "stdout": process.stdout, "stderr": process.stderr}
        except subprocess.TimeoutExpired:
            result = {"source": str(source), "timed_out": True}
        outcomes.append(result)
        print(source.parent.parent.name, source.parent.name, result.get("returncode", "timeout"), flush=True)
        write_json(batch / "rtf_rendering.json", outcomes)


if __name__ == "__main__":
    main()
