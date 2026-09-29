/* Synthetic WORK inputs only; child labels deliberately repeat under parents. */
data work.ra_adsl;
  length USUBJID $2;
  input USUBJID $ VALUE1;
  datalines;
01 2
02 4
;
run;

data work.ra_records;
  length USUBJID $2 GROUP_VALUE CHILD_VALUE $1;
  input USUBJID $ SEQ GROUP_VALUE $ GROUPN CHILD_VALUE $ CHILDN VALUE1 VALUE2;
  datalines;
01 1 A 1 X 1 2 12
02 2 A 1 Y 2 4 14
01 3 B 2 X 1 10 110
02 4 B 2 Y 2 20 120
;
run;
