/* Assertions fail the current SAS submission with a stable fixture message. */

%macro assert_stat(dataset=, statistic=, expected=, row=row_001, tolerance=1e-12);
  %local fixture_rows fixture_matches;
  proc sql noprint;
    select count(*),
           sum(estimable = 1 and abs(value - (&expected)) <= (&tolerance))
      into :fixture_rows trimmed, :fixture_matches trimmed
      from &dataset
      where row_id = "&row"
        and statistic_id = "&statistic"
        and column_order = 1;
  quit;
  %if &fixture_rows ne 1 or &fixture_matches ne 1 %then %do;
    %put ERROR: [FIXTURE] statistic_assertion_failed dataset=&dataset row=&row statistic=&statistic expected=&expected rows=&fixture_rows matches=&fixture_matches.;
    %abort cancel;
  %end;
%mend;

%macro assert_unit_counts(dataset=, expected_rows=, expected_nonmissing=, expected_missing=);
  %local fixture_rows fixture_nonmissing fixture_missing;
  proc sql noprint;
    select count(*),
           sum(not missing(analysis_value)),
           sum(missing(analysis_value))
      into :fixture_rows trimmed, :fixture_nonmissing trimmed, :fixture_missing trimmed
      from &dataset;
  quit;
  %if &fixture_rows ne &expected_rows or
      &fixture_nonmissing ne &expected_nonmissing or
      &fixture_missing ne &expected_missing %then %do;
    %put ERROR: [FIXTURE] unit_count_assertion_failed dataset=&dataset rows=&fixture_rows nonmissing=&fixture_nonmissing missing=&fixture_missing.;
    %abort cancel;
  %end;
%mend;
