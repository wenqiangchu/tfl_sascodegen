# Complete metadata cell keys and accumulate each requested statistic once.

expected_cell_skeleton_source <- function(plan) {
  suffix <- sprintf("%03d", plan$batch_order)
  map_dataset <- paste0("_TFL_KEY_MAP_", suffix)
  key_dataset <- paste0("_TFL_KEY_", suffix)
  # Header-independent metadata needs one copy; the full logical map remains
  # available to emitters while SAS expands the shared column catalog.
  entries <- Filter(function(entry) isTRUE(entry$column_order == 1L),
                    plan$result_map %||% list())
  fields <- c("chunk_order", "chunk_id", "row_order", "row_id", "row_type", "label",
              "indent_level", "statistic_id",
              "statistic_order", "digits_mode", "digits_value", "use_header_n", "cell_format")
  character_lengths <- c(
    chunk_id = "&_TFL_ID_LEN.", row_id = "&_TFL_ID_LEN.", row_type = "16",
    label = "&_TFL_LABEL_LEN.",
    statistic_id = "16", digits_mode = "16", cell_format = "&_TFL_CELL_LEN."
  )
  needs_restore <- function(value) {
    grepl("[\r\n]", value) || grepl(";;;;", value, fixed = TRUE)
  }
  restorations <- unlist(lapply(seq_along(entries), function(index) {
    entry <- entries[[index]]
    unlist(lapply(names(character_lengths), function(field) {
      value <- entry[[field]]
      if (!needs_restore(value)) return(character())
      # Inline records cannot contain physical line breaks or their terminator.
      # Restore these rare values after INPUT; ordinary fields stay readable.
      hex <- paste(sprintf("%02X", as.integer(charToRaw(enc2utf8(value)))), collapse = "")
      paste0("  if _n_ = ", index, " then ", field, " = '", hex, "'x;")
    }), use.names = FALSE)
  }), use.names = FALSE)
  data_rows <- vapply(entries, function(entry) {
    vapply(fields, function(field) {
      value <- entry[[field]]
      if (is.character(value)) {
        # Quote character fields so labels and cell formats may contain the
        # DSD delimiter or spaces without changing the row shape.
        value <- gsub("\r", "\\r", value, fixed = TRUE)
        value <- gsub("\n", "\\n", value, fixed = TRUE)
        value <- gsub(";;;;", "\\x3B\\x3B\\x3B\\x3B", value, fixed = TRUE)
        paste0('"', gsub('"', '""', value, fixed = TRUE), '"')
      } else as.character(value)
    }, character(1L)) |> paste(collapse = "|")
  }, character(1L))
  input_fields <- vapply(fields, function(field) {
    if (field %in% names(character_lengths)) {
      # Macro delimiters and informat terminators each require their own dot.
      paste0(field, " :$", character_lengths[[field]], ".")
    } else paste0(field, " :best32.")
  }, character(1L))
  data_statement <- if (any(grepl(";", data_rows, fixed = TRUE))) "datalines4" else "datalines"
  c(
    "/* Expand the complete chunk/row/header/statistic expected-cell skeleton. */",
    paste0("data ", map_dataset, ";"),
    "  length chunk_id row_id $&_TFL_ID_LEN label $&_TFL_LABEL_LEN cell_format $&_TFL_CELL_LEN;",
    "  length row_type statistic_id digits_mode $16;",
    paste0("  infile ", data_statement, " dlm='|' dsd truncover;"),
    "  input",
    paste0("    ", input_fields),
    "  ;",
    restorations,
    paste0("  ", data_statement, ";"),
    data_rows,
    if (identical(data_statement, "datalines4")) ";;;;" else ";",
    "run;",
    "/* Expand every declared header column, including columns with no population members. */",
    "proc sql noprint;",
    paste0("  create table ", key_dataset, " as"),
    "  select m.*, h.header_column_id, h.column_order,",
    if (!is.null(plan$nodes_dataset)) {
      "    n.node_key, n.group_path, n.node_label, n.node_order_path, n.hierarchy_level"
    } else c(
      "    ' ' as node_key length=1, ' ' as group_path length=1,",
      "    ' ' as node_label length=&_TFL_LABEL_LEN, ' ' as node_order_path length=1,",
      "    0 as hierarchy_level"
    ),
    paste0("  from ", map_dataset, " as m"),
    paste0("  cross join ", plan$header_columns_dataset, " as h"),
    if (!is.null(plan$nodes_dataset)) paste0("  cross join ", plan$nodes_dataset, " as n"),
    paste0("  order by m.chunk_order, m.row_order, h.column_order, m.statistic_order",
           if (!is.null(plan$nodes_dataset)) ", n.node_order_path", ";"),
    "quit;"
  )
}

statistic_digits_source <- function() {
  c(
    "  resolved_digits = .;",
    "  if digits_mode = 'absolute' then resolved_digits = digits_value;",
    "  else if digits_mode = 'relative' then resolved_digits = coalesce(base_digits, 0) + digits_value;",
    "  if resolved_digits < 0 and not missing(resolved_digits) then do;",
    "    putlog 'ERROR: [USER] Relative digits resolved to a negative value.';",
    "    estimable = 0; resolved_digits = .;",
    "  end;"
  )
}

render_long_form_source <- function(plan, cell_format = "cell_format") {
  suffix <- sprintf("%03d", plan$batch_order)
  c(
    "/* Render long-form statistics into independent row/header cells. */",
    paste0("proc sort data=", plan$statistic_dataset, " out=_TFL_RSTAT_", suffix, ";"),
    "  by chunk_order node_key row_order column_order statistic_order;",
    "run;",
    paste0("data ", plan$render_dataset, ";"),
    "  length cell_text $&_TFL_CELL_LEN token $256 runtime_row_id $&_TFL_RUNTIME_LEN row_role $16;",
    "  retain cell_text;",
    paste0("  set _TFL_RSTAT_", suffix, ";"),
    "  by chunk_order node_key row_order column_order;",
    paste0("  if first.column_order then cell_text = ", cell_format, ";"),
    "  if row_type = 'analysis' then do;",
    "    if estimable = 0 then token = 'NE';",
    "    else if statistic_id = 'n' then token = strip(PUTN(value, '32.'));",
    "    else do;",
    "      rounded_value = ROUND(value, 10 ** (-resolved_digits));",
    "      if rounded_value = 0 then rounded_value = 0;",
    "      token = strip(PUTN(rounded_value, cats('F', 32, '.', resolved_digits)));",
    "    end;",
    "    cell_text = TRANWRD(cell_text, cats('{', statistic_id, '}'), strip(token));",
    "  end;",
    "  else cell_text = '';",
    "  if missing(cell_text) then cell_text = '';",
    "  row_sequence = row_order; runtime_row_id = row_id; row_role = row_type;",
    "  if last.column_order then output;",
    "  keep chunk_id row_id label indent_level header_column_id cell_text",
    "    chunk_order row_order row_sequence column_order runtime_row_id row_role",
    "    node_key group_path node_label node_order_path hierarchy_level;",
    "run;"
  )
}
