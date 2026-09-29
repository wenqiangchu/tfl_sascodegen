%include "prepare_data.sas";
%include "assertions.sas";
%include "generated/record.sas";

%assert_stat(dataset=work._TFL_STAT_002, statistic=n, expected=2);
%assert_stat(dataset=work._TFL_STAT_002, statistic=mean, expected=15);

%put NOTE: [FIXTURE] record counting unit passed.;
