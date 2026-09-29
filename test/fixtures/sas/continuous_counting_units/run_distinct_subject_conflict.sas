%include "prepare_data.sas";
%include "generated/distinct_subject_conflict.sas";

/* The generated program must ABORT CANCEL before reaching this fallback. */
%put ERROR: [FIXTURE] fixture_expected_abort_missing.;
%abort cancel;
