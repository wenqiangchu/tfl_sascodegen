/* Fresh process per sample; -sysparm is records_blocks_mode. */
options errorabend;
%let bench_records=%scan(&sysparm,1,_);
%let bench_blocks=%scan(&sysparm,2,_);
%let bench_mode=%scan(&sysparm,3,_);
libname bench "generated";
data work.ra_adsl;
  length USUBJID $12;
  do subject=1 to &bench_records/2;
    USUBJID=put(subject,z12.);
    output;
  end;
  keep USUBJID;
run;
data work.ra_records;
  set work.ra_adsl;
  length GROUP_VALUE $4;
  array values[4] VALUE1-VALUE4;
  do SEQ=1 to 2;
    GROUPN=mod(_n_,10)+1;
    GROUP_VALUE=cats('G',put(GROUPN,z2.));
    do index=1 to 4;
      values[index]=mod(_n_*index+SEQ,1000)/10;
    end;
    output;
  end;
  keep USUBJID SEQ GROUP_VALUE GROUPN VALUE1-VALUE4;
run;
/* Time generation steps only; exclude SAS startup and synthetic preparation. */
data _null_;
  call symputx('bench_start',put(datetime(),best32.));
run;
%include "generated/benchmark_&bench_blocks._&bench_mode..sas";
data _null_;
  elapsed=datetime()-input(symget('bench_start'),best32.);
  putlog 'NOTE: [BENCH] elapsed_seconds=' elapsed best16.6;
run;

/* End-of-generation file bytes, not peak WORK or process memory. */
proc sql noprint;
  select sum(filesize) format=32. into :bench_bytes trimmed from dictionary.tables
    where libname='WORK' and memtype='DATA' and substr(memname,1,5)='_TFL_';
quit;
%put NOTE: [BENCH] final_intermediate_bytes=&bench_bytes.;
data bench.w&bench_records._&bench_blocks._&bench_mode;
  set work._TFL_WIDE_001;
run;
data bench.s&bench_records._&bench_blocks._&bench_mode;
  set work._TFL_STAT_001;
run;
%put NOTE: [BENCH] completed &sysparm.;
