"""Compare Word layout, exact table content, indentation, widths and pagination."""
from pathlib import Path
import argparse
import json
import sys

from PIL import Image, ImageChops
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "test/fixtures/sas/runtime_v2"))
from runner import write_json
from run_formats import read_table


def paragraph_text(cell):
    return tuple(p["text"] for p in cell["paragraphs"])


def flat_text(cell):
    return "".join(paragraph_text(cell))


def single_paragraph_text(cell):
    paragraphs = paragraph_text(cell)
    return paragraphs[0] if len(paragraphs) == 1 else None


def normalized_whitespace(text):
    # PDF extraction may insert line breaks where Word wraps a long header label.
    return " ".join(text.split())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--baseline-batch", default="initial")
    args = parser.parse_args()
    workspace = ROOT / "study/validation_v2"
    cases = json.loads((workspace / "cases.json").read_text())
    outcomes = []
    for case in cases:
        current = workspace / "runs" / args.batch / case["case_id"] / "current"
        baseline = workspace / "runs" / args.baseline_batch / case["case_id"] / "baseline"
        original = workspace / "runs/original_rtf" / case["case_id"]
        layout = json.loads((current / "visual/layout.json").read_text())
        old = json.loads((baseline / "visual/layout.json").read_text())
        historical = json.loads((original / "visual/layout.json").read_text())
        checks = []
        def check(name, passed, detail=None):
            checks.append(dict(check=name, passed=bool(passed), detail=detail))
        check("original_rtf_matches_rerun_layout", old == historical)
        original_pages = sorted((original / "visual").glob("page-*.png"))
        baseline_pages = sorted((baseline / "visual").glob("page-*.png"))
        check("original_rtf_matches_rerun_pixels", len(original_pages)==len(baseline_pages) and all(
            ImageChops.difference(Image.open(a).convert("RGB"),Image.open(b).convert("RGB")).getbbox() is None
            for a,b in zip(original_pages,baseline_pages)))
        asm = read_table(current / "results", "_tfl_asm_001").sort_values("report_order")
        header_n = read_table(current / "results", "_tfl_hn_001").sort_values("column_order").header_n.tolist()
        check("one_table_with_all_columns", len(layout["tables"])==1 and len(layout["tables"][0]["grid"])==5)
        rows = [r for t in layout["tables"] for r in t["rows"] if not r["header"]]
        check("body_row_count", len(rows)==len(asm))
        for i, (row, (_, expected)) in enumerate(zip(rows,asm.iterrows()),1):
            expected_text = [str(expected.label)] + [str(expected[f"col_{j:03d}"]) for j in range(1,5)]
            check("body_exact_text", [single_paragraph_text(c) for c in row["cells"]] == expected_text, i)
            check("stub_indent", int(row["cells"][0]["paragraphs"][0]["indent"].get("left",0)) == 200*expected.indent_level, i)
            check("treatment_alignment", all(c["paragraphs"][0]["alignment"].get("val")=="center" for c in row["cells"][1:]), i)
        headers = [r for r in layout["tables"][0]["rows"] if r["header"]]
        check("spanning_header", [single_paragraph_text(c) for c in headers[0]["cells"]]==["","Treatment"] and headers[0]["cells"][1]["span"]=={"val":"4"})
        check("header_column_order", [single_paragraph_text(c) for c in headers[1]["cells"]][1:]==[c["label"] for c in case["header"]["columns"]])
        # PROC REPORT SPLIT='/' explicitly breaks the metadata stub header.
        check("stub_header", single_paragraph_text(headers[2]["cells"][0]) == "".join(s.strip() for s in case["template"]["body"]["stub_header"].split("/")))
        check("header_n_text", [single_paragraph_text(c) for c in headers[2]["cells"]][1:]==[f"(N = {int(n)})" for n in header_n])
        section = layout["sections"][0]
        printable = int(section["size"]["w"])-int(section["margins"]["left"])-int(section["margins"]["right"])
        widths = [int(c["w"]) for c in layout["tables"][0]["grid"]]
        requested = [c["width"]*1440 for c in case["header"]["columns"]]
        border_twips = 2 * 0.75 / 72 * 1440
        expected_stub = printable - sum(requested) - border_twips
        # Record Word's exact rounding/rescaling; do not normalize it away.
        check("rendered_widths_within_one_point", len(widths) == len(requested) + 1 and
              abs(widths[0] - expected_stub) <= 20 and
              all(abs(a-b)<=20 for a,b in zip(widths[1:],requested)),
              {"twips": widths, "requested_stub_twips": expected_stub,
               "requested_treatment_twips": requested,
               "delta_stub_twips": widths[0] - expected_stub,
               "delta_treatment_twips": [a-b for a,b in zip(widths[1:],requested)]})
        check("table_fits_printable_width", sum(widths)<=printable, {"table_twips":sum(widths),"printable_twips":printable})
        pdf = PdfReader(current / "visual/report.pdf")
        check("page_count", len(pdf.pages)==layout["pages"]==len(list((current / "visual").glob("page-*.png"))))
        for i,page in enumerate(pdf.pages,1):
            page_text=normalized_whitespace(page.extract_text())
            expected_page_header = [c["label"] for c in case["header"]["columns"]] + [f"(N = {int(n)})" for n in header_n]
            check("page_has_repeated_headers", all(normalized_whitespace(value) in page_text for value in expected_page_header),
                  {"page": i, "expected": expected_page_header})
        passed = all(c["passed"] for c in checks)
        failed_checks = {c["check"] for c in checks if not c["passed"]}
        if passed:
            classification = "Historical horizontal-panel layout corrected; hierarchy rows/order independently validated where applicable."
        elif "page_has_repeated_headers" in failed_checks:
            classification = "Content/layout checks completed; at least one rendered page lacks the expected repeated header."
        else:
            classification = "One or more RTF content, structure, width, or pagination checks failed."
        outcome = dict(case=case["case_id"], passed=passed,
                       pages=dict(original=historical["pages"],baseline=old["pages"],current=layout["pages"]),
                       classification=classification,
                       checks=checks)
        write_json(current.parent / "rtf_comparison.json", outcome)
        outcomes.append({k:v for k,v in outcome.items() if k!="checks"})
        print(case["case_id"], outcome["passed"], [c for c in checks if not c["passed"]][:5], flush=True)
    write_json(workspace / "runs" / args.batch / "rtf_results.json", outcomes)
    if not all(outcome["passed"] for outcome in outcomes):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
