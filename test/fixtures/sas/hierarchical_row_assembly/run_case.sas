/* Run in a fresh external SAS process with one case name in -sysparm. */
options errorabend;
%let fixture_case=&sysparm;
%include "prepare_data.sas";
%include "generated/&fixture_case..sas";
%include "generated/&fixture_case._expected.sas";

%macro assert_row_assembly;
  %local expected_count actual_count mismatch expected_spacers expected_total distinct_positions;
  %let expected_spacers=0;
  %if &fixture_case=multilevel %then %let expected_spacers=3;
  %if &fixture_case=mixed %then %let expected_spacers=2;
  proc sql noprint;
    select count(*) into :expected_count trimmed from work.ra_expected;
    select count(*) into :actual_count trimmed from work._TFL_CELLS_001;
  quit;
  %if &actual_count ne %eval(&expected_count * 3) %then %do;
    %put ERROR: [FIXTURE] long_cell_count case=&fixture_case.;
    %abort cancel;
  %end;

  /* Every logical row has exactly one cell in each displayed header column. */
  proc sql noprint;
    create table work.ra_bad_rows as
    select chunk_order, row_sequence from work._TFL_CELLS_001
    group by chunk_order, row_sequence
    having count(*) ne 3 or count(distinct column_order) ne 3
      or min(column_order) ne 1 or max(column_order) ne 3
      or count(distinct runtime_row_id) ne 1;
    select count(*) into :mismatch trimmed from work.ra_bad_rows;
  quit;
  %if &mismatch ne 0 %then %do;
    %put ERROR: [FIXTURE] row_identity_or_column_collision case=&fixture_case.;
    %abort cancel;
  %end;

  /* Compare all row identities, order, labels, indentation and column values. */
  /* No ID statement: observation order is itself part of the expectation. */
  proc compare base=work.ra_expected compare=work._TFL_WIDE_001
    method=absolute criterion=0 noprint;
    var chunk_order row_sequence chunk_id row_id runtime_row_id node_key
        row_role hierarchy_level label indent_level col_001 col_002 col_003;
  run;
  %if &sysinfo ne 0 %then %do;
    %put ERROR: [FIXTURE] absolute_wide_rows case=&fixture_case sysinfo=&sysinfo.;
    %abort cancel;
  %end;

  data work.ra_assembled;
    set work._TFL_ASM_001;
    if row_role ne 'spacer';
    keep chunk_order row_sequence chunk_id row_id runtime_row_id node_key
         row_role hierarchy_level label indent_level col_001 col_002 col_003;
  run;
  proc compare base=work.ra_expected compare=work.ra_assembled
    method=absolute criterion=0 noprint;
    var chunk_order row_sequence chunk_id row_id runtime_row_id node_key
        row_role hierarchy_level label indent_level col_001 col_002 col_003;
  run;
  %if &sysinfo ne 0 %then %do;
    %put ERROR: [FIXTURE] absolute_assembled_rows case=&fixture_case sysinfo=&sysinfo.;
    %abort cancel;
  %end;

  %let expected_total=%eval(&expected_count + &expected_spacers);
  proc sql noprint;
    select count(*) into :actual_count trimmed from work._TFL_ASM_001;
    select count(distinct report_order) into :distinct_positions trimmed from work._TFL_ASM_001;
    select count(*) into :mismatch trimmed from work._TFL_ASM_001
      where row_role='spacer'
        and (not missing(label) or not missing(col_001) or not missing(col_002)
             or not missing(col_003) or indent_level ne 0);
  quit;
  %if &actual_count ne &expected_total or &distinct_positions ne &expected_total or &mismatch ne 0 %then %do;
    %put ERROR: [FIXTURE] assembled_spacing case=&fixture_case.;
    %abort cancel;
  %end;
  /* Fixed report positions detect spacers inserted at the wrong boundaries. */
  data _null_;
    set work._TFL_ASM_001;
    if row_role='spacer' then do;
      if ("&fixture_case"='multilevel' and report_order not in (7, 11, 17)) or
         ("&fixture_case"='mixed' and report_order not in (9, 11)) then do;
        putlog 'ERROR: [FIXTURE] spacer_position';
        abort cancel;
      end;
    end;
  run;
  %put NOTE: [FIXTURE] row assembly &fixture_case passed rows=&expected_count.;
%mend;
%assert_row_assembly;
