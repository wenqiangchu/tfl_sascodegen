"""Render preserved copies of the seven original RTFs with the same Word worker."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]


def main():
    workspace=ROOT/"study/validation_v2"
    for case in json.loads((workspace/"cases.json").read_text()):
        output=workspace/"runs/original_rtf"/case["case_id"]
        output.mkdir(parents=True,exist_ok=True)
        target=output/"original.rtf"
        original=ROOT/case["old_rtf"]
        if target.exists():
            assert target.read_bytes()==original.read_bytes()
        else:
            shutil.copy2(original,target)
        if (output/"visual/layout.json").exists():
            continue
        subprocess.run([sys.executable,str(Path(__file__).with_name("render_rtf.py")),
                        "--source",str(target),"--output",str(output/"visual")],
                       check=True,timeout=150,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))


if __name__=="__main__":
    main()
