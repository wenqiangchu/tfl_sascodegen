/* Synthetic WORK data for hierarchical continuous counting-unit validation. */

data work.cu_adsl;
  length USUBJID $8;
  input USUBJID $;
  datalines;
01
02
;
run;

data work.cu_record;
  length USUBJID $8 GROUP_VALUE $12;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN AVAL;
  datalines;
01 1 GROUP_A 1 1 10
01 2 GROUP_A 1 1 20
02 3 GROUP_A 1 1 .
;
run;

data work.cu_distinct_subject;
  length USUBJID $8 GROUP_VALUE $12;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN AVAL;
  datalines;
01 1 GROUP_A 1 1 10
01 2 GROUP_A 1 2 .
02 3 GROUP_A 1 1 .
02 4 GROUP_A 1 2 .
;
run;

data work.cu_distinct_key;
  length USUBJID $8 GROUP_VALUE $12;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN AVAL;
  datalines;
01 1 GROUP_A 1 1 120
01 2 GROUP_A 1 1 .
02 3 GROUP_A 1 2 .
02 4 GROUP_A 1 2 .
;
run;

data work.cu_distinct_subject_conflict;
  length USUBJID $8 GROUP_VALUE $12;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN AVAL;
  datalines;
01 1 GROUP_A 1 1 10
01 2 GROUP_A 1 2 20
02 3 GROUP_A 1 1 .
;
run;

data work.cu_shared_level;
  length USUBJID $8 GROUP_VALUE $12 FLAG $1;
  input USUBJID $ RECORD_ID GROUP_VALUE $ GROUP_ORDER AVISITN AVAL FLAG $;
  datalines;
01 1 GROUP_A 1 1 10 Y
01 2 GROUP_A 1 2 20 N
02 3 GROUP_A 1 1 30 Y
;
run;
