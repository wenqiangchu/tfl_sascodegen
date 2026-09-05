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
  c(
    "/* Expand the complete chunk/row/header/statistic expected-cell skeleton. */",
    paste0("data _TFL_KEY_", sprintf("%03d", plan$batch_order), ";"),
    "  length chunk_id row_id header_column_id statistic_id $128;",
    "  /* result_map supplies label and analysis identities in template order. */",
    "  /* Missing raw cells are retained with numeric missing value and estimable=0. */",
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
