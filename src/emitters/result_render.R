# Shared long-form statistic and render source fragments.

long_form_statistic_source <- function(plan, raw_value = "value") {
  c(
    "/* Map analysis output to the common long-form statistic identity. */",
    paste0("data ", plan$statistic_dataset, ";"),
    "  length chunk_id row_id header_column_id statistic_id $128;",
    paste0("  set ", plan$raw_dataset, ";"),
    "  /* chunk_id, row_id, header_column_id and statistic_id come from the plan map. */",
    paste0("  value = ", raw_value, ";"),
    "  if missing(value) then estimable = 0; else estimable = 1;",
    "  /* resolved_digits is carried per statistic; n leaves it missing. */",
    "run;"
  )
}

expected_cell_skeleton_source <- function(plan) {
  result_map <- plan$result_map %||% list()
  map_rows <- if (length(result_map) > 0L) {
    vapply(result_map, function(entry) {
      paste(c(
        sas_character_literal(entry$chunk_id %||% ""),
        sas_character_literal(entry$row_id %||% ""),
        sas_character_literal(entry$header_column_id %||% ""),
        sas_character_literal(entry$statistic_id %||% ""),
        as.integer(entry$row_order %||% 0L),
        as.integer(entry$column_order %||% 0L)
      ), collapse = "|")
    }, character(1L))
  } else character()
  c(
    "/* Expand the complete chunk/row/header/statistic expected-cell skeleton. */",
    paste0("data _TFL_KEY_", sprintf("%03d", plan$batch_order), ";"),
    "  length chunk_id row_id header_column_id statistic_id $128;",
    "  infile datalines dlm='|' dsd truncover;",
    "  input chunk_id :$128. row_id :$128. header_column_id :$128.",
    "        statistic_id :$128. row_order column_order;",
    if (length(map_rows) > 0L) c("  datalines;", map_rows, ";") else
      "  /* Empty result maps are valid for chunks without analysis rows. */",
    "  /* Missing raw cells remain represented by this complete key skeleton. */",
    "run;"
  )
}

render_long_form_source <- function(plan, cell_format = "cell_format") {
  c(
    "/* Render long-form statistics into independent row/header cells. */",
    paste0("data ", plan$render_dataset, ";"),
    "  length chunk_id row_id label header_column_id cell_text token $256;",
    paste0("  set ", plan$statistic_dataset, ";"),
    "  if estimable = 0 then token = 'NE';",
    "  else if statistic_id = 'n' then token = PUTN(value, 'BEST32.');",
    "  else do;",
    "    rounded_value = ROUND(value, 10 ** (-resolved_digits));",
    "    if rounded_value = 0 then rounded_value = 0;",
    "    token = PUTN(rounded_value, cats('F', 32, '.', resolved_digits));",
    "  end;",
    paste0("  cell_text = TRANWRD(", cell_format,
           ", cats('{', statistic_id, '}'), token);"),
    "  if missing(cell_text) then cell_text = '';",
    "run;"
  )
}
