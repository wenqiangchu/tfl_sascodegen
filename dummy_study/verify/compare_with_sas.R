#!/usr/bin/env Rscript
# Compare the SAS output cells against the independent R computation.
#
# The report layout is node-driven: a hierarchical node occupies one label row
# with empty cells, and its statistics live on the rows directly beneath it. A
# flat chunk prints only statistic rows. Both shapes are resolved to
# (path, column, stat) before joining, so a missing node fails as loudly as a
# wrong number.
#
# Numbers are compared at the precision the cell actually displays. The rendered
# value is already rounded, so asserting 6.4542400 against "6.45" at full
# precision would test float formatting rather than the statistic; the digit
# count is therefore read back from the cell itself.
#
# Usage (from the repository root):
#   Rscript dummy_study/verify/compare_with_sas.R

suppressPackageStartupMessages(library(haven))

sas_dir <- file.path("dummy_study", "generated", "sasout")
expected_path <- file.path("dummy_study", "generated", "expected", "expected.csv")
report_path <- file.path("dummy_study", "generated", "comparison.csv")

if (!file.exists(expected_path)) {
  stop("Run compute_expected.R first: ", expected_path, call. = FALSE)
}

expected <- utils::read.csv(expected_path, stringsAsFactors = FALSE)

# Report column position -> header column id. The shift table's columns are
# baseline grades rather than treatment arms, so the mapping is per table.
columns_for <- function(table) {
  if (identical(table, "t_14_2_3_hgb_shift")) {
    return(c(col_001 = "bl_normal", col_002 = "bl_low", col_003 = "bl_high",
             col_004 = "overall"))
  }
  c(col_001 = "placebo", col_002 = "low", col_003 = "high", col_004 = "overall")
}

# Statistic rows are labelled with the statistics they display. Several
# statistics share one row ("Mean (SD)", "Q1, Q3"), so a row maps to a set.
stat_row_map <- list(
  "n" = c(n = "n"),
  "Mean (SD)" = c(mean = "mean", sd = "sd"),
  "Median" = c(median = "median"),
  "Q1, Q3" = c(q1 = "q1", q3 = "q3"),
  "Min, Max" = c(min = "min", max = "max")
)

# Pull the slice-th number out of a rendered cell and record how many decimals
# the cell printed, so the comparison can round to the same precision.
cell_number <- function(text, slice) {
  empty <- list(value = NA_real_, digits = 0L)
  text <- trimws(as.character(text))
  if (length(text) != 1L || is.na(text) || text == "" || grepl("^NE", text)) {
    return(empty)
  }
  numbers <- regmatches(text, gregexpr("[-+]?[0-9]+([.][0-9]+)?", text))[[1L]]
  index <- slice + 1L
  if (index > length(numbers)) return(empty)
  token <- numbers[[index]]
  digits <- if (grepl("[.]", token)) nchar(sub(".*[.]", "", token)) else 0L
  list(value = suppressWarnings(as.numeric(token)), digits = digits)
}

read_wide <- function(table) {
  path <- file.path(sas_dir, paste0("wide_", table, ".sas7bdat"))
  if (!file.exists(path)) stop("Missing SAS output: ", path, call. = FALSE)
  data <- haven::read_sas(path)
  data$label <- trimws(as.character(data$label))
  data
}

build_cell <- function(table, path, column_id, stat, text, slice) {
  parsed <- cell_number(text, slice)
  data.frame(table = table, path = path, column_id = column_id, stat = stat,
             text = text, value = parsed$value, digits = parsed$digits,
             stringsAsFactors = FALSE)
}

empty_cells <- function() {
  data.frame(table = character(), path = character(), column_id = character(),
             stat = character(), text = character(), value = numeric(),
             digits = integer(), stringsAsFactors = FALSE)
}

# Hierarchical layout: node rows have no cell values; statistic rows follow.
flatten_hierarchical <- function(data, table, columns) {
  cells <- list()
  has_values <- rep(FALSE, nrow(data))
  for (column_name in names(columns)) {
    if (!column_name %in% names(data)) next
    values <- as.character(data[[column_name]])
    has_values <- has_values | (!is.na(values) & trimws(values) != "")
  }
  current <- character(0)
  current_path <- NA_character_
  for (i in seq_len(nrow(data))) {
    label <- data$label[[i]]
    if (!has_values[[i]]) {
      # A node at level L replaces whatever was recorded at that level, so
      # sibling nodes do not accumulate into one another.
      level <- data$hierarchy_level[[i]]
      if (is.na(level) || level <= 0L) level <- 1L
      current <- c(current[seq_len(min(length(current), level - 1L))], label)
      current_path <- paste(current, collapse = " / ")
      next
    }
    stat_set <- stat_row_map[[label]]
    if (is.null(stat_set)) next
    for (column_name in names(columns)) {
      if (!column_name %in% names(data)) next
      text <- as.character(data[[column_name]][[i]])
      for (position in seq_along(stat_set)) {
        cells[[length(cells) + 1L]] <- build_cell(
          table, current_path, unname(columns[[column_name]]),
          unname(stat_set[[position]]), text, position - 1L)
      }
    }
  }
  if (length(cells) == 0L) return(empty_cells())
  do.call(rbind, cells)
}

# Flat layout: every row is printed on its own. A continuous characteristic
# prints one row per statistic; a category level prints "n (pct%)".
resolve_flat_paths <- function(data) {
  chunk_titles <- c(age = "Age (years)",
                    bmi = "Baseline Body Mass Index (kg/m2)",
                    disease_duration = "Disease Duration (months)")
  shift_sections <- c(shift_placebo = "Placebo",
                      shift_low = "Xanomeline Low Dose",
                      shift_high = "Xanomeline High Dose")
  paths <- character(nrow(data))
  for (i in seq_len(nrow(data))) {
    chunk <- trimws(as.character(data$chunk_id[[i]]))
    label <- data$label[[i]]
    row_id <- trimws(as.character(data$row_id[[i]]))
    if (chunk %in% names(shift_sections)) {
      # The printed row label is only the worst grade, so the arm is part of the
      # path to keep the three sections apart.
      paths[[i]] <- paste(shift_sections[[chunk]], label, sep = " / ")
    } else if (chunk %in% names(chunk_titles) &&
               grepl("_(n|mean|median|q1|min)$", row_id)) {
      paths[[i]] <- chunk_titles[[chunk]]
    } else {
      paths[[i]] <- label
    }
  }
  data$path <- paths
  data
}

# Flat chunks come in three shapes, and `row_role` plus `hierarchy_level` say
# which: a hierarchy node carries its own counts on the same row (dynamic), a
# below row sits under the node it belongs to (static), and a continuous or
# category row prints "n (pct%)" or one line per statistic. A static row also
# carries a hierarchy level, so it must be appended to the current path rather
# than truncating it like a node would.
flatten_mixed <- function(data, table, columns) {
  cells <- list()
  current <- character(0)
  for (i in seq_len(nrow(data))) {
    label <- data$label[[i]]
    level <- data$hierarchy_level[[i]]
    role <- as.character(data$row_role[[i]])
    is_node <- !is.na(level) && level > 0L && !identical(role, "static")
    if (is_node) {
      current <- c(current[seq_len(min(length(current), level - 1L))], label)
      path <- paste(current, collapse = " / ")
      stat_set <- c(n = "n", pct = "pct")
    } else if (!is.na(level) && level > 0L) {
      # A below row: keep the node path and append the row label.
      path <- paste(c(current, label), collapse = " / ")
      stat_set <- c(n = "n", pct = "pct")
    } else {
      stat_set <- if (label %in% names(stat_row_map)) {
        stat_row_map[[label]]
      } else {
        c(n = "n", pct = "pct")
      }
      path <- data$path[[i]]
    }
    for (column_name in names(columns)) {
      if (!column_name %in% names(data)) next
      text <- as.character(data[[column_name]][[i]])
      if (is.na(text) || trimws(text) == "") next
      for (position in seq_along(stat_set)) {
        cells[[length(cells) + 1L]] <- build_cell(
          table, path, unname(columns[[column_name]]),
          unname(stat_set[[position]]), text, position - 1L)
      }
    }
  }
  if (length(cells) == 0L) return(empty_cells())
  do.call(rbind, cells)
}

key_of <- function(frame) {
  paste(frame$path, frame$column_id, frame$stat, sep = "\r")
}

callculate_status <- function(expected_rows, actual_rows, table) {
  missing <- expected_rows[!key_of(expected_rows) %in% key_of(actual_rows), ]
  extra <- actual_rows[!key_of(actual_rows) %in% key_of(expected_rows), ]
  joined <- merge(expected_rows, actual_rows[, c("path", "column_id", "stat",
                                                 "value", "digits")],
                  by = c("path", "column_id", "stat"),
                  suffixes = c("_expected", "_actual"))

  asserted <- joined[joined$asserted, ]
  # Round the expected value to the digits the cell printed. Base round() uses
  # round-half-to-even while SAS ROUND() rounds halves away from zero, so a value
  # ending in exactly 5 would disagree; apply the SAS rule explicitly.
  sas_round <- function(value, digits) {
    scale <- 10^digits
    sign(value) * floor(abs(value) * scale + 0.5) / scale
  }
  expected_rounded <- vapply(seq_len(nrow(asserted)), function(i) {
    sas_round(asserted$value_expected[[i]], asserted$digits[[i]])
  }, numeric(1L))
  actual_rounded <- asserted$value_actual
  mismatched <- asserted[!is.na(asserted$value_expected) &
                           (is.na(actual_rounded) |
                              abs(expected_rounded - actual_rounded) > 1e-9), ]
  both_na <- asserted[is.na(asserted$value_expected) & is.na(actual_rounded), ]

  list(
    summary = data.frame(
      table = table, expected = nrow(expected_rows), matched = nrow(joined),
      asserted = nrow(asserted), mismatched = nrow(mismatched),
      missing = nrow(missing), extra = nrow(extra),
      both_not_estimable = nrow(both_na),
      reported_only = nrow(joined) - nrow(asserted),
      stringsAsFactors = FALSE),
    problems = list(
      if (nrow(mismatched) > 0L) data.frame(
        table = table, path = mismatched$path, column_id = mismatched$column_id,
        stat = mismatched$stat, value_expected = mismatched$value_expected,
        value_actual = mismatched$value_actual, kind = "value",
        stringsAsFactors = FALSE),
      if (nrow(missing) > 0L) data.frame(
        table = table, path = missing$path, column_id = missing$column_id,
        stat = missing$stat, value_expected = missing$value,
        value_actual = NA_real_, kind = "missing_in_sas",
        stringsAsFactors = FALSE),
      if (nrow(extra) > 0L) data.frame(
        table = table, path = extra$path, column_id = extra$column_id,
        stat = extra$stat, value_expected = NA_real_, value_actual = extra$value,
        kind = "unexpected_in_sas", stringsAsFactors = FALSE)))
}

# The visit table nests PARAM > visit; everything else is flat.
hierarchical_tables <- c("t_14_3_2_1_hgb_by_visit")

summaries <- list()
problems <- list()
for (table in unique(expected$table)) {
  expected_rows <- expected[expected$table == table, ]
  data <- read_wide(table)
  columns <- columns_for(table)
  actual_rows <- if (table %in% hierarchical_tables) {
    flatten_hierarchical(data, table, columns)
  } else {
    flatten_mixed(resolve_flat_paths(data), table, columns)
  }
  outcome <- callculate_status(expected_rows, actual_rows, table)
  summaries[[table]] <- outcome$summary
  problems <- c(problems, outcome$problems)
}

summary_table <- do.call(rbind, summaries)
utils::write.csv(summary_table, report_path, row.names = FALSE)

for (i in seq_len(nrow(summary_table))) {
  row <- summary_table[i, ]
  ok <- row$mismatched == 0L && row$missing == 0L && row$extra == 0L
  cat(sprintf("%-28s expected=%4d matched=%4d asserted=%4d not-estimable=%4d %s\n",
              row$table, row$expected, row$matched, row$asserted,
              row$both_not_estimable, if (ok) "ok" else "PROBLEM"))
}

problems <- Filter(Negate(is.null), problems)
if (length(problems) > 0L) {
  combined <- do.call(rbind, problems)
  cat(sprintf("\n%d problem cell(s); first 20:\n", nrow(combined)))
  for (i in seq_len(min(nrow(combined), 20L))) {
    cat(sprintf("  %-46s %-8s %-6s expected=%-12s actual=%-12s %s\n",
                substr(combined$path[[i]], 1, 46), combined$column_id[[i]],
                combined$stat[[i]], format(combined$value_expected[[i]]),
                format(combined$value_actual[[i]]), combined$kind[[i]]))
  }
  cat(sprintf("\nsummary: %s\n", report_path))
  quit(status = 1L)
}

cat(sprintf("\nall %d asserted cells agree with the independent R computation\n",
            sum(summary_table$asserted)))
cat(sprintf("summary: %s\n", report_path))
