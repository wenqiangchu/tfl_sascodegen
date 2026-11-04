"""Audit allocated UTF-8 lengths and the exact SOC/PT presentation sequence."""
from pathlib import Path
import argparse

from runner import write_json
from run_formats import read_table

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    args = parser.parse_args()
    batch = ROOT / "study/validation_v2/runs" / args.batch
    checks=[]
    def check(name, passed, detail=None):
        checks.append(dict(check=name,passed=bool(passed),detail=detail))
    for case,key_width,label_width in [("basic",79,256),("long_labels",1849,1080)]:
        results=batch/"synthetic"/case/"results"
        inventory=read_table(results,"column_inventory")
        descriptors=inventory[inventory.memname.str.startswith("_TFL_HNODES")]
        for name,width in [("node_key",key_width),("parent_node_key",key_width),("group_path",key_width),("node_label",label_width),("node_order_path",22)]:
            actual=descriptors[descriptors.name==name].length.tolist()
            check("allocated_width",actual==[width,width],dict(case=case,field=name,actual=actual,expected=width))
        for level in (1,2):
            nodes=read_table(results,f"_tfl_hnodes_001_{level:03d}")
            check("labels_fit_bytes",nodes.node_label.map(lambda v:len(v.encode("utf-8"))).max()<=label_width,case)
            check("keys_fit_bytes",nodes.node_key.map(lambda v:len(v.encode("utf-8"))).max()<=key_width,case)
    asm=read_table(batch/"severity_case/results","_tfl_asm_001")
    expected=[]
    previous_depth=None
    for path in ["GI","GI/Diarrhoea","GI/Nausea","Neuro","Neuro/Headache"]:
        depth=path.count("/")
        if previous_depth is not None and previous_depth!=depth:
            expected.append(("",0,"spacer"))
        expected.append((path.split("/")[-1],depth,"dynamic"))
        expected.extend((label,depth+1,"static") for label in ["Mild","Moderate","Severe"])
        previous_depth=depth
    actual=list(asm[["label","indent_level","row_role"]].itertuples(index=False,name=None))
    check("severity_exact_rows_labels_indents_and_spacing",actual==expected)
    totals=asm[(asm.row_id=="total") & (asm.row_role!="spacer")]
    check("five_soc_pt_totals_on_node_rows",len(totals)==5 and (totals.row_role=="dynamic").all() and (totals.col_001!="").all())
    write_json(batch/"lengths_severity_assertions.json",checks)
    print("Assertions",len(checks),"failed",sum(not c["passed"] for c in checks))
    if not all(c["passed"] for c in checks):
        raise SystemExit(1)


if __name__=="__main__":
    main()
