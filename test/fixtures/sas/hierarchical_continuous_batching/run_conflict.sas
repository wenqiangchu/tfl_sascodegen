/* Run separately with -sysparm subject_conflict or key_conflict. */
%include "prepare_data.sas";
%let fixture_case=&sysparm;
%include "generated/&fixture_case._shared.sas";
%put ERROR: [FIXTURE] expected_second_block_abort_missing.;
%abort cancel;
