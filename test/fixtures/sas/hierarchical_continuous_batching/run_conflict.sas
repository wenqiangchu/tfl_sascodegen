/* Run separately with -sysparm subject_conflict or key_conflict. */
%include "prepare_data.sas";
%let fixture_case=&sysparm;
%include "generated/&fixture_case._shared.sas";
/* The unit conflict is reported as a warning instead of cancelling the
   submission, so reaching this note is the expected outcome. A cancelled run
   never prints it, which makes its absence the failure signal. */
%put NOTE: [FIXTURE] expected_second_block_warning_reached.;
