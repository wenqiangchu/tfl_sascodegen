/* Synthetic data only: overlapping columns, typed keys and different precisions. */
data work.hb_adsl;
  length USUBJID $8;
  input USUBJID $;
  datalines;
01
02
03
;
run;

data work.hb_subject;
  length USUBJID $8 GROUP_VALUE $12;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN VALUE1 VALUE2;
  datalines;
01 1 A 1 1 1.2 .
01 2 A 1 1 . 10.125
02 3 A 1 .A 2.4 20.25
02 4 A 1 .A . .
03 5 A 1 . . .
03 6 A 1 . . .
01 7 B 2 1 7 .A
02 8 B 2 1 8 .
;
run;

data work.hb_record;
  set work.hb_subject;
  if RECORD_ID = 2 then VALUE1 = 3.6;
run;

data work.hb_four;
  set work.hb_record;
  VALUE3 = VALUE1 + 100;
  VALUE4 = VALUE2 + 1000;
run;

data work.hb_varied work.hb_negative;
  set work.hb_record;
run;

data work.hb_key;
  set work.hb_subject end=last_record;
  output;
  if last_record then do;
    USUBJID = '01'; RECORD_ID = 9; GROUP_VALUE = 'A'; GROUP_ORDER = 1;
    AVISITN = 2; VALUE1 = 36.4; VALUE2 = 30.375;
    output;
  end;
  drop last_record;
run;

data work.hb_empty;
  set work.hb_subject(obs=0);
run;

data work.hb_missing;
  set work.hb_subject;
  VALUE1 = .; VALUE2 = .A;
run;

/* Equal nonmissing values are still two records and must cause a conflict. */
data work.hb_subject_conflict work.hb_key_conflict;
  set work.hb_subject;
  if RECORD_ID = 1 then VALUE2 = 10.125;
run;
