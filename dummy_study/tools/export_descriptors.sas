/* Export variable descriptors (label, type, format) for the dummy study data.
   Run once per data refresh; the result is committed so the Markdown
   dictionary can be rebuilt without SAS. */

%let root = G:\projects\tfl_sascodegen\dummy_study;

libname indata "&root.\data" access=readonly;

proc contents data=indata.adsl out=work.c_adsl noprint; run;
proc contents data=indata.adae out=work.c_adae noprint; run;
proc contents data=indata.adlbh out=work.c_adlbh noprint; run;

data work.descriptors;
  length domain $8;
  set work.c_adsl(in=ina)
      work.c_adae(in=inb)
      work.c_adlbh(in=inc);
  if ina then domain = 'adsl';
  else if inb then domain = 'adae';
  else domain = 'adlbh';
  keep domain varnum name type length label format formatl nobs;
run;

proc sort data=work.descriptors; by domain varnum; run;

proc export data=work.descriptors
  outfile="&root.\variables\descriptors.csv"
  dbms=csv replace;
run;
