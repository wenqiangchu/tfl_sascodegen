%include "prepare_data.sas";
%include "assertions.sas";
%include "generated/distinct_subject.sas";

%assert_unit_counts(
  dataset=work._TFL_CUNIT_002,
  expected_rows=2,
  expected_nonmissing=1,
  expected_missing=1
);
%assert_stat(dataset=work._TFL_STAT_002, statistic=n, expected=1);
%assert_stat(dataset=work._TFL_STAT_002, statistic=mean, expected=10);

%put NOTE: [FIXTURE] distinct_subject counting unit passed.;
