"""Generate the dummy study variable dictionary.

Descriptors (label, type, length, format) come from `variables/descriptors.csv`,
which `tools/export_descriptors.sas` produces with SAS `PROC CONTENTS`. Value
distributions come from the data itself. Keeping the descriptors as a committed
file means the dictionary can be rebuilt without a SAS installation, and the
script fails loudly if the descriptor row count disagrees with the data.

Run from anywhere:
    python dummy_study/tools/build_variable_dictionary.py
"""
from __future__ import annotations

import csv
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "variables"
DESCRIPTORS = OUT / "descriptors.csv"

# Show concrete values while the domain stays small enough to read.
MAX_LISTED = 12

# SAS dates are days since 1960-01-01; datetimes are seconds since the same epoch.
SAS_EPOCH_DATE = date(1960, 1, 1)
SAS_EPOCH_DATETIME = datetime(1960, 1, 1)
DATE_FORMAT_PREFIXES = (
    "DATE", "DAY", "DDMMYY", "DOWNAME", "E8601DA", "JULIAN", "JULDAY", "MMDDYY",
    "MMYY", "MONNAME", "MONTH", "MONYY", "QTR", "WEEKDATE", "WEEKDAY", "WORDDATE",
    "WORDDATX", "YEAR", "YYMM", "YYMMDD", "YYQ", "YYMON",
)
DATETIME_FORMAT_PREFIXES = ("DATETIME", "E8601DT", "TOD", "TIME", "HHMM")


def load_descriptors():
    """Group PROC CONTENTS rows by domain, preserving VARNUM order."""
    if not DESCRIPTORS.exists():
        raise SystemExit(
            f"Missing {DESCRIPTORS.relative_to(ROOT.parent)}.\n"
            "Run: sas tools/export_descriptors.sas (see README)."
        )
    grouped = {}
    with DESCRIPTORS.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            grouped.setdefault(row["domain"], []).append(row)
    for rows in grouped.values():
        rows.sort(key=lambda r: int(r["VARNUM"]))
    return grouped


def is_char(descriptor):
    return str(descriptor["TYPE"]).strip() == "2"


def numeric_text(value):
    """Render a number without a spurious .0 while keeping real decimals."""
    as_float = float(value)
    if as_float.is_integer():
        return str(int(as_float))
    return f"{as_float:g}"


def format_kind(fmt):
    """Classify a SAS format name so dates can be rendered readably."""
    name = "".join(ch for ch in (fmt or "").upper() if ch.isalpha())
    if not name:
        return "none"
    if name.startswith(DATETIME_FORMAT_PREFIXES):
        return "datetime"
    if name.startswith(DATE_FORMAT_PREFIXES):
        return "date"
    return "other"


def render_numeric(value, kind):
    if kind == "date":
        try:
            return (SAS_EPOCH_DATE + timedelta(days=int(value))).isoformat()
        except (OverflowError, ValueError):
            return numeric_text(value)
    if kind == "datetime":
        try:
            return (SAS_EPOCH_DATETIME + timedelta(seconds=float(value))).isoformat()
        except (OverflowError, ValueError):
            return numeric_text(value)
    return numeric_text(value)


def escape(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def value_summary(series, descriptor):
    """Summarise observed values: an explicit list when short, else a range."""
    observed = series.dropna()
    distinct = int(observed.nunique())
    if distinct == 0:
        return 0, "（全部缺失）"

    if is_char(descriptor):
        values = sorted({str(v).strip() for v in observed.unique()})
        if distinct <= MAX_LISTED:
            return distinct, ", ".join(f"`{escape(v)}`" for v in values)
        head = ", ".join(f"`{escape(v)}`" for v in values[:MAX_LISTED])
        return distinct, f"共 {distinct} 个不同值，前 {MAX_LISTED} 个：{head}"

    # pandas decodes SAS variables that carry a date/datetime format into
    # datetime64, which pd.to_numeric would turn into nanoseconds since 1970.
    # Render those directly instead of leaking the epoch value.
    if pd.api.types.is_datetime64_any_dtype(observed):
        rendered = sorted(observed.dt.strftime("%Y-%m-%d").unique())
        if distinct <= MAX_LISTED:
            return distinct, ", ".join(f"`{value}`" for value in rendered)
        return distinct, f"{rendered[0]} – {rendered[-1]}"

    kind = format_kind(descriptor.get("FORMAT"))
    numeric = pd.to_numeric(observed, errors="coerce").dropna()
    if numeric.empty:
        return distinct, "（无数值）"
    low, high = numeric.min(), numeric.max()
    if distinct <= MAX_LISTED:
        values = sorted(numeric.unique())
        listed = ", ".join(f"`{render_numeric(v, kind)}`" for v in values)
        return distinct, listed
    return distinct, f"{render_numeric(low, kind)} – {render_numeric(high, kind)}"


def build_domain(domain, descriptors):
    path = DATA / f"{domain}.sas7bdat"
    frame = pd.read_sas(path, format="sas7bdat", encoding="latin1")
    for column in frame.columns:
        if frame[column].dtype == object:
            # Strip padding like SAS STRIP(), but keep missing values missing:
            # astype(str) would otherwise turn them into the literal 'nan'.
            values = frame[column]
            missing = values.isna()
            values = values.astype(str).str.strip().mask(missing)
            frame[column] = values

    nobs = len(frame)
    if len(frame.columns) != len(descriptors):
        raise SystemExit(
            f"{domain}: data has {len(frame.columns)} variables but "
            f"descriptors.csv has {len(descriptors)}. Re-run tools/export_descriptors.sas."
        )

    lines = [
        f"# {domain.upper()} 变量字典",
        "",
        f"数据文件：`dummy_study/data/{domain}.sas7bdat`　观测数：**{nobs}**　"
        f"变量数：**{len(descriptors)}**",
        "",
        "由 `dummy_study/tools/build_variable_dictionary.py` 生成，请勿手工编辑。",
        "标签/类型/长度/格式来自 `variables/descriptors.csv`（SAS `PROC CONTENTS`）；"
        "取值分布来自数据本身。",
        "",
        "## 变量一览",
        "",
        "| # | 变量 | 类型 | 长度 | 标签 | 格式 | 非缺失 | 不同值 | 取值 / 范围 |",
        "| ---: | --- | --- | ---: | --- | --- | ---: | ---: | --- |",
    ]

    for index, descriptor in enumerate(descriptors, start=1):
        name = descriptor["NAME"]
        if name not in frame.columns:
            raise SystemExit(f"{domain}.{name} is in descriptors.csv but not in the data.")
        series = frame[name]
        kind = "char" if is_char(descriptor) else "num"
        distinct, summary = value_summary(series, descriptor)
        label = escape(descriptor["LABEL"] or "")
        fmt = escape(descriptor["FORMAT"] or "")
        if fmt:
            # Descriptors store the format name without its trailing period.
            fmt = f"{fmt}."
        lines.append(
            f"| {index} | {name} | {kind} | {descriptor['LENGTH']} | {label} | {fmt} | "
            f"{int(series.notna().sum())} | {distinct} | {summary} |"
        )

    lines.extend([
        "",
        "## 说明",
        "",
        f"- 不同值不超过 {MAX_LISTED} 个的变量直接列出全部取值；超过的给出范围。",
        "- 带 `DATE*`/`YYMMDD*` 等日期格式的数值变量按 SAS 1960-01-01 纪元换算成 ISO 日期显示。",
        "- 字符变量的前后空格已去除，与 SAS 侧 `strip()` 的口径一致。",
        "",
    ])
    return "\n".join(lines)


def main():
    grouped = load_descriptors()
    missing = sorted(set(grouped) - {p.stem for p in DATA.glob("*.sas7bdat")})
    if missing:
        raise SystemExit(f"descriptors.csv lists domains with no data file: {missing}")

    OUT.mkdir(parents=True, exist_ok=True)
    for domain in sorted(grouped):
        text = build_domain(domain, grouped[domain])
        target = OUT / f"{domain}.md"
        target.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {target.relative_to(ROOT.parent)} ({len(grouped[domain])} variables)")


if __name__ == "__main__":
    main()
