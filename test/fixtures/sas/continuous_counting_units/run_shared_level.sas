%include "prepare_data.sas";
%include "assertions.sas";
%include "generated/shared_level.sas";

%assert_stat(dataset=work._TFL_STAT_002, statistic=n, expected=3);
%assert_stat(dataset=work._TFL_STAT_002, statistic=mean, expected=20);
%assert_stat(
  dataset=work._TFL_STAT_003,
  row=category_row_001,
  statistic=n,
  expected=2
);
%assert_stat(
  dataset=work._TFL_STAT_003,
  row=category_row_001,
  statistic=pct,
  expected=100
);

%put NOTE: [FIXTURE] shared anchor-level membership expansion passed.;
