# Shared source preparation keeps membership expansion explicit in SAS.

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

# The subject identifier is fixed by the portable contract; carrying it as a
# per-chunk field only created a second place for the same value to drift.
subject_key_constant <- function() "USUBJID"

source_block_duplicate_guard <- function(dataset, position_keys, check_keys, suffix,
                                         scope_field = NULL) {
  # An empty check key list means this counting unit has no duplicate concept.
  if (!length(check_keys)) return(character())
  keys <- c(position_keys, check_keys)
  source_duplicate_guard(dataset, keys, suffix, scope_field = scope_field)
}

primitive_source_input <- function(plan, entry, source_dataset, merged_dataset, kind) {
  chunk <- entry$chunk
  nested <- !is.null(plan$nodes_dataset)
  subject_key <- subject_key_constant()
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
  # The identity key says which records collapse into one counted unit. It is
  # consumed by NODUPKEY and by every grouping that must agree with counting,
  # so it must never be empty: an empty BY list silently turns NODUPKEY into a
  # whole-table collapse.
  switch(unit,
         record = "source_row",
         distinct_subject = "USUBJID",
         distinct_key = chunk$distinct_key,
         stop("Unsupported counting unit.", call. = FALSE))
}

denominator_counting_keys <- function(denominator) {
  primitive_counting_keys(list(counting_unit = denominator$unit,
                              distinct_key = denominator$distinct_key))
}

denominator_uses_header_n <- function(denominator) {
  !is.null(denominator) &&
    identical(denominator$scope, "header_population") &&
    identical(denominator$unit, "distinct_subject") &&
    is.null(denominator$expression)
}

primitive_check_keys <- function(chunk, unit = chunk$counting_unit %||% "distinct_subject") {
  # Which keys deserve a duplicate warning. record counts each source row on its
  # own, so source_row is unique by construction and a check could never fire.
  # That is a property of the check, not of record identity, so it is kept
  # separate from primitive_counting_keys().
  if (identical(unit, "record")) return(character())
  primitive_counting_keys(chunk, unit)
}
