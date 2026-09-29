%include "prepare_data.sas";
%include "assertions.sas";
%include "generated/distinct_key.sas";

%assert_unit_counts(
  dataset=work._TFL_CUNIT_002,
  expected_rows=2,
  expected_nonmissing=1,
  expected_missing=1
);
%assert_stat(dataset=work._TFL_STAT_002, statistic=n, expected=1);
%assert_stat(dataset=work._TFL_STAT_002, statistic=mean, expected=120);

%put NOTE: [FIXTURE] typed distinct_key counting unit passed.;
