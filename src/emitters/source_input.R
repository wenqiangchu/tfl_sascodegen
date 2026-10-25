# Shared source preparation keeps membership expansion explicit in SAS.

source_auto_dedup_guard <- function(input_dataset, keys, suffix) {
  if (!length(keys)) {
    return(list(source = character(), dataset = input_dataset))
  }
  sorted <- paste0("_TFL_DEDUP_", suffix)
  list(
    dataset = sorted,
    source = c(
      "/* Keep one source record per key and drop the remaining duplicates. */",
      "/* Which record survives is PROC SORT's sorted-first choice; see the user guide. */",
      paste0("proc sort data=", input_dataset, " out=", sorted, " nodupkey;"),
      paste0("  by ", paste(keys, collapse = " "), ";"),
      "run;"
    )
  )
}

source_duplicate_guard <- function(dataset, keys, suffix, scope_field = NULL) {
  if (!length(keys)) return(character())
  last_key <- tail(keys, 1L)
  c(
    "/* Warn about duplicate source keys without dropping source records. */",
    paste0("proc sort data=", dataset, " out=_TFL_GUARD_", suffix, ";"),
    paste0("  by ", paste(keys, collapse = " "), ";"),
    "run;",
    "data _null_;",
    paste0("  set _TFL_GUARD_", suffix, ";"),
    paste0("  by ", paste(keys, collapse = " "), ";"),
    paste0("  if first.", last_key, " then _tfl_key_count = 0;"),
    "  _tfl_key_count + 1;",
    paste0("  if last.", last_key, " and _tfl_key_count > 1 then"),
    if (!is.null(scope_field)) {
      paste0("    putlog 'WARNING: [USER] duplicate_key unit=' ", last_key,
             " ' scope=", scope_field, " ' ", scope_field,
             " ' count=' _tfl_key_count '.';")
    } else {
      paste0("    putlog 'WARNING: [USER] duplicate_key unit=' ", last_key,
             " ' count=' _tfl_key_count '.';")
    },
    "run;"
  )
}

primitive_source_filter <- function(plan, entry, source_dataset, kind) {
  chunk <- entry$chunk
  c(
    paste0("/* Filter ", kind, " chunk source before merge. */"),
    paste0("data ", source_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;"),
    "  source_row = _n_;",
    "run;"
  )
}

primitive_source_input <- function(plan, entry, source_dataset, merged_dataset, kind) {
  chunk <- entry$chunk
  nested <- !is.null(plan$nodes_dataset)
  subject_key <- plan$subject_key %||% "USUBJID"
  if (isTRUE(plan$membership_expanded_source)) {
    return(c(
      paste0("/* Read shared node/header membership source for nested ", kind, " analysis. */"),
      paste0("data ", merged_dataset, ";"),
      paste0("  set ", chunk$source_data, ";"),
      "run;"
    ))
  }
  c(
    paste0("/* Filter ", kind, " chunk source before merge. */"),
    paste0("data ", source_dataset, ";"),
    paste0("  set ", chunk$source_data, ";"),
    if (!is.null(chunk$filter)) paste0("  if not (", chunk$filter, ") then delete;"),
    "  source_row = _n_;",
    "run;",
    if (isTRUE(plan$include_duplicate_check) && !nested)
      source_duplicate_guard(source_dataset, subject_key,
                             sprintf("%03d_%03d", plan$batch_order, entry$chunk_order)),
    paste0("/* Merge ", kind, " chunk source with header membership. */"),
    "/* SQL expands each source record into every applicable header column. */",
    "proc sql noprint;",
    paste0("  create table ", merged_dataset, " as"),
    "  select m.USUBJID, m.header_column_id, m.column_order, s.*",
    paste0("  from ", plan$membership_dataset, " as m ", if (nested) "inner" else "left", " join"),
    paste0("    ", source_dataset, "(rename=(", subject_key, "=_TFL_SOURCE_SUBJECT)) as s"),
    "  on m.USUBJID = s._TFL_SOURCE_SUBJECT;",
    "quit;"
  )
}

primitive_counting_keys <- function(chunk, unit = chunk$counting_unit %||% "distinct_subject") {
  switch(unit,
         record = "source_row",
         distinct_subject = "USUBJID",
         distinct_key = chunk$distinct_key,
         stop("Unsupported counting unit.", call. = FALSE))
}
