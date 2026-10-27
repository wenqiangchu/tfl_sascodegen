%include "prepare_data.sas";
%include "generated/distinct_subject_conflict.sas";

/* The generated program now reports the conflict as a warning instead of
   cancelling the submission, so reaching this note is the expected outcome.
   A cancelled run never prints it, which makes absence the failure signal. */
%put NOTE: [FIXTURE] fixture_expected_warning_reached.;
