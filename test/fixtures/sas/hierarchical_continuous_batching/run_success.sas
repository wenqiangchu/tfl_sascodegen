/* Pass record, four, varied, negative, subject, key, empty or missing with -sysparm. */
%include "prepare_data.sas";

%macro compare_dataset(base=, actual=, keys=);
  proc sort data=&actual out=work.hb_actual;
    by &keys;
  run;
  proc compare base=&base compare=work.hb_actual method=absolute criterion=1e-12 noprint;
    id &keys;
  run;
  %if &sysinfo ne 0 %then %do;
    %put ERROR: [FIXTURE] shared_independent_mismatch dataset=&actual sysinfo=&sysinfo.;
    %abort cancel;
  %end;
%mend;

/* Generated programs run in open code so their global length macros are visible. */
%let fixture_case=&sysparm;
%let block_count=%sysfunc(ifc(%eval(&fixture_case=four),4,2));

%macro result_descriptors(output=);
  %local index;
  proc sql noprint;
    create table &output as
    select memname, varnum, name, type, length, format, informat, label
    from dictionary.columns
    where libname='WORK' and memname in (
      %do index=2 %to %eval(&block_count + 1);
        %if &index > 2 %then ,;
        "_TFL_KEY_MAP_00&index", "_TFL_KEY_00&index", "_TFL_CJOIN_00&index",
        "_TFL_STAT_00&index", "_TFL_RSTAT_00&index", "_TFL_REND_00&index"
      %end;
    )
    order by memname, varnum;
  quit;
%mend;

%macro assert_absolute_row_count;
  %local expected_rows actual_rows actual_cells;
  %let expected_rows=%eval(2 * &block_count);
  %if &fixture_case=varied %then %let expected_rows=8;
  %if &fixture_case=empty %then %let expected_rows=0;
  proc sql noprint;
    select count(*) into :actual_rows trimmed from work._TFL_WIDE_001;
    select count(*) into :actual_cells trimmed from work._TFL_CELLS_001;
  quit;
  %if &actual_rows ne &expected_rows or &actual_cells ne %eval(&expected_rows * 3) %then %do;
    %put ERROR: [FIXTURE] absolute_row_count_failed case=&fixture_case.;
    %abort cancel;
  %end;
%mend;

%put NOTE: [FIXTURE] begin independent &fixture_case.;
%include "generated/&fixture_case._independent.sas";
%assert_absolute_row_count;

%macro save_baseline;
  %local index;
  proc sort data=work._TFL_STAT_001 out=work.hb_base_stat;
    by analysis_id node_key row_id column_order statistic_id;
  run;
  proc sort data=work._TFL_REND_001 out=work.hb_base_render;
    by runtime_row_id column_order;
  run;
  %do index=2 %to %eval(&block_count + 1);
    proc sort data=work._TFL_CRAW_00&index out=work.hb_base_raw_&index;
      by chunk_order node_key column_order;
    run;
    proc sort data=work._TFL_CPREC_00&index out=work.hb_base_precision_&index;
      by chunk_order node_key;
    run;
    proc sort data=work._TFL_STAT_00&index out=work.hb_base_private_stat_&index;
      by chunk_order node_key row_order column_order statistic_order;
    run;
    proc sort data=work._TFL_REND_00&index out=work.hb_base_private_render_&index;
      by chunk_order node_key row_order column_order;
    run;
  %end;
  %result_descriptors(output=work.hb_base_descriptors);
%mend;
%save_baseline;

/* Missing shared outputs must not inherit results from the independent run. */
proc datasets library=work nolist;
  delete _TFL_:;
quit;

%put NOTE: [FIXTURE] begin shared &fixture_case.;
%include "generated/&fixture_case._shared.sas";
%assert_absolute_row_count;

%macro assert_results;
  %local index fixture_count;
  %compare_dataset(base=work.hb_base_stat, actual=work._TFL_STAT_001,
                   keys=analysis_id node_key row_id column_order statistic_id);
  %compare_dataset(base=work.hb_base_render, actual=work._TFL_REND_001,
                   keys=runtime_row_id column_order);
  %do index=2 %to %eval(&block_count + 1);
    %compare_dataset(base=work.hb_base_raw_&index, actual=work._TFL_CRAW_00&index,
                     keys=chunk_order node_key column_order);
    %compare_dataset(base=work.hb_base_precision_&index, actual=work._TFL_CPREC_00&index,
                     keys=chunk_order node_key);
    %compare_dataset(base=work.hb_base_private_stat_&index, actual=work._TFL_STAT_00&index,
                     keys=chunk_order node_key row_order column_order statistic_order);
    %compare_dataset(base=work.hb_base_private_render_&index, actual=work._TFL_REND_00&index,
                     keys=chunk_order node_key row_order column_order);
  %end;
  %result_descriptors(output=work.hb_actual_descriptors);
  %compare_dataset(base=work.hb_base_descriptors, actual=work.hb_actual_descriptors,
                   keys=memname varnum);

  proc sql noprint;
    select count(*) into :fixture_count trimmed from work.hb_actual_descriptors
      where substr(memname,1,10)='_TFL_STAT_';
  quit;
  %if &fixture_count ne %eval(32 * &block_count) %then %do;
    %put ERROR: [FIXTURE] private_statistic_schema_changed.;
    %abort cancel;
  %end;

  /* Check absolute outcomes as well as paired equivalence. */
  %if &fixture_case=subject %then %do;
    proc sql noprint;
      select count(*) into :fixture_count trimmed
        from work._TFL_STAT_001
        where node_label='A' and column_order=1 and statistic_id='mean'
          and ((analysis_id='analysis_1' and abs(value-1.8)<1e-12 and resolved_digits=1)
            or (analysis_id='analysis_2' and abs(value-15.1875)<1e-12 and resolved_digits=4));
    quit;
    %if &fixture_count ne 2 %then %do;
      %put ERROR: [FIXTURE] absolute_mean_or_precision_failed.;
      %abort cancel;
    %end;
  %end;
  %if &fixture_case ne empty %then %do;
    proc sql noprint;
      select count(*) into :fixture_count trimmed from work._TFL_STAT_001
        where column_order=3
          and ((statistic_id='n' and value ne 0)
            or (statistic_id ne 'n' and estimable ne 0));
    quit;
    %if &fixture_count ne 0 %then %do;
      %put ERROR: [FIXTURE] empty_header_cells_failed.;
      %abort cancel;
    %end;
  %end;
  %if &fixture_case=negative %then %do;
    proc sql noprint;
      select count(*) into :fixture_count trimmed from work._TFL_STAT_001
        where statistic_id='mean' and estimable=0 and missing(resolved_digits);
    quit;
    %if &fixture_count ne 12 %then %do;
      %put ERROR: [FIXTURE] negative_digits_contract_changed.;
      %abort cancel;
    %end;
    proc sql noprint;
      select count(*) into :fixture_count trimmed from work._TFL_STAT_001
        where statistic_id='n' and estimable=1 and missing(resolved_digits);
    quit;
    %if &fixture_count ne 12 %then %do;
      %put ERROR: [FIXTURE] negative_digits_leaked_into_other_statistics.;
      %abort cancel;
    %end;
  %end;
  %put NOTE: [FIXTURE] shared continuous &fixture_case passed.;
%mend;
%assert_results;
