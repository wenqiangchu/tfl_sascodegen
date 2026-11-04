# Counts are derived from the seven literal records below, not generated results.
denominator_case <- function() {
  definitions <- list(
    header = list(scope = "header_population", unit = "distinct_subject"),
    qualified_header = list(scope = "header_population", unit = "distinct_subject", expression = "HQUAL='Y'"),
    records = list(scope = "chunk_source", unit = "record", expression = "EVAL='Y'"),
    subjects = list(scope = "chunk_source", unit = "distinct_subject", expression = "EVAL='Y'"),
    cycles = list(scope = "chunk_source", unit = "distinct_key", distinct_key = "CYCLE", expression = "EVAL='Y'"),
    zero = list(scope = "chunk_source", unit = "record", expression = "0"))
  expected_denominators <- list(header = c(3,1,0), qualified_header = c(2,1,0),
    records = c(4,2,0), subjects = c(2,1,0), cycles = c(2,2,0), zero = c(0,0,0))
  block <- function(id, denominator, unit = "distinct_subject", nested = FALSE) {
    value <- list(id = id, type = "categorical_summary_nonexclusive", counting_unit = unit,
      denominator = denominator, rows = list(list(id = id, type = "analysis", label = id,
        condition = "HIT='Y'", statistics = list(list(id = "n"), list(id = "pct", digits = 1L)),
        cell_format = "{n}|{pct}")))
    if (unit == "distinct_key") value$distinct_key <- c("USUBJID", "CYCLE")
    if (nested) { value$anchor_level <- "group"; value$placement <- "below" } else {
      value$source_data <- "work.rv_events"
    }
    value
  }
  chunks <- lapply(names(definitions), function(id) block(paste0("top_", id), definitions[[id]]))
  chunks <- c(chunks, list(block("top_record_n", definitions$cycles, "record"),
                          block("top_key_n", definitions$cycles, "distinct_key")))
  nested_definitions <- c(definitions, list(
    local_records = list(scope = "current_group", unit = "record", expression = "EVAL='Y'"),
    local_subjects = list(scope = "current_group", unit = "distinct_subject", expression = "EVAL='Y'"),
    local_cycles = list(scope = "current_group", unit = "distinct_key", distinct_key = "CYCLE", expression = "EVAL='Y'")))
  nested <- lapply(names(nested_definitions), function(id) block(paste0("nested_", id), nested_definitions[[id]], nested = TRUE))
  chunks[[length(chunks) + 1L]] <- list(id = "hier", type = "hierarchical_summary", source_data = "work.rv_events",
    levels = list(list(id = "group", variable = "GROUP", order_variable = "GROUP", order_direction = "asc",
                       node_role = "label", missing_policy = "exclude")), analysis_blocks = nested)
  before <- c(
    "data work.rv_adsl; length USUBJID $2 HQUAL $1; input USUBJID $ HQUAL $; datalines;",
    "01 Y", "02 N", "03 Y", ";", "run;",
    "data work.rv_events; length USUBJID $2 GROUP EVAL HIT $1; input USUBJID $ CYCLE SEQ GROUP $ EVAL $ HIT $; datalines;",
    "01 1 1 A N Y", "01 1 2 A Y Y", "01 2 3 B Y N", "02 1 4 A Y Y", "02 2 5 . Y Y", "03 3 6 B N Y", "04 4 7 A Y Y", ";", "run;"
  )
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "work.rv_adsl", orientation = "landscape",
      columns = lapply(1:3, function(i) list(id = paste0("c", i), label = c("All", "Subset", "Empty")[[i]],
        condition = c("1", "USUBJID='01'", "0")[[i]], display_order = i, width = 1, alignment = "center")))),
    tables = list(list(id = "rv_denominators", population_id = "p", header_id = "h", template_id = "t",
                       custom_code = list(before = paste(before, collapse = "\n")))),
    templates = list(list(id = "t", body = list(stub_header = "Denominators", chunks = chunks))))
  expected <- list()
  add <- function(id, path, n, denominator) {
    expected[[length(expected) + 1L]] <<- list(row_id = id, path = path, n = n, denominator = denominator)
  }
  for (id in names(definitions)) add(paste0("top_", id), "", c(3,1,0), expected_denominators[[id]])
  add("top_record_n", "", c(5,2,0), expected_denominators$cycles)
  add("top_key_n", "", c(4,1,0), expected_denominators$cycles)
  for (group in c("A", "B")) {
    n <- if (group == "A") c(2,1,0) else c(1,0,0)
    for (id in names(definitions)) add(paste0("nested_", id), group, n, expected_denominators[[id]])
    add("nested_local_records", group, n, if (group == "A") c(2,1,0) else c(1,1,0))
    add("nested_local_subjects", group, n, if (group == "A") c(2,1,0) else c(1,1,0))
    add("nested_local_cycles", group, n, c(1,1,0))
  }
  list(bundle = bundle, expected = expected, header_n = c(3,1,0))
}
