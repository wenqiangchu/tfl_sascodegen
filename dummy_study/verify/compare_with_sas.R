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

# The cell comparison is keyed by report path, so it is blind to display order.
# For a format-driven table the order is exactly what the format decides, so the
# rendered sequence is compared against the order derived from the declaration.
# Without this, dropping NOTSORTED reorders the table and every cell still agrees.
# The report path of a row: a node keeps the ancestors above its own depth, so a
# level-2 node replaces the previous level-2 entry rather than appending to it,
# and a `static` (below) row keeps the node path and appends its own label. Both
# the order check and the cell comparison must use this one definition, or they
# can disagree about which row is which.
report_paths <- function(labels, levels, roles) {
  current <- character(0)
  paths <- character(length(labels))
  for (index in seq_along(labels)) {
    level <- levels[[index]]
    role <- as.character(roles[[index]])
    if (!is.na(level) && level > 0L && !identical(role, "static")) {
      current <- c(current[seq_len(min(length(current), level - 1L))], labels[[index]])
      paths[[index]] <- paste(current, collapse = " / ")
    } else if (!is.na(level) && level > 0L) {
      paths[[index]] <- paste(c(current, labels[[index]]), collapse = " / ")
    } else {
      paths[[index]] <- NA_character_
    }
  }
  paths
}

check_node_order <- function(table) {
  order_path <- file.path("dummy_study", "generated", "expected", "node_order.csv")
  if (!file.exists(order_path)) return(NULL)
  expected_order <- utils::read.csv(order_path, stringsAsFactors = FALSE)
  expected_order <- expected_order[expected_order$table == table, ]
  if (nrow(expected_order) == 0L) return(NULL)

  asm_path <- file.path(sas_dir, paste0("asm_", table, ".sas7bdat"))
  if (!file.exists(asm_path)) {
    stop("Missing assembled SAS output: ", asm_path, call. = FALSE)
  }
  assembled <- haven::read_sas(asm_path)
  assembled <- assembled[order(assembled$report_order), ]
  assembled$label <- trimws(as.character(assembled$label))
  assembled <- assembled[as.character(assembled$row_role) != "spacer", ]

  paths <- report_paths(assembled$label, assembled$hierarchy_level, assembled$row_role)

  list(
    table = table,
    actual = paths,
    expected = expected_order$path,
    agrees = identical(paths, expected_order$path)
  )
}

# A format supplies node values the data does not contain, so the interesting
# contract for a format-driven table is that the zero-count nodes are *printed*
# rather than dropped. Value comparison cannot show that: an absent node has no
# cell to disagree with. This asserts the shape directly.
check_format_nodes <- function(table, expected_shape) {
  asm_path <- file.path(sas_dir, paste0("asm_", table, ".sas7bdat"))
  if (!file.exists(asm_path)) return(NULL)
  assembled <- haven::read_sas(asm_path)
  assembled <- assembled[order(assembled$report_order), ]
  rows <- assembled[as.character(assembled$row_role) != "spacer", ]
  levels <- rows$hierarchy_level
  columns <- grep("^col_[0-9]+$", names(rows), value = TRUE)
  zero <- rep(TRUE, nrow(rows))
  for (column in columns) {
    zero <- zero & trimws(as.character(rows[[column]])) == "0 (0.0%)"
  }

  parents <- rows[!is.na(levels) & levels == 1L, ]
  children <- rows[!is.na(levels) & levels == 2L, ]
  parent_zero <- zero[!is.na(levels) & levels == 1L]
  child_zero <- zero[!is.na(levels) & levels == 2L]

  actual <- c(parents = nrow(parents), zero_parents = sum(parent_zero),
              children = nrow(children), zero_children = sum(child_zero),
              non_zero = sum(!zero))
  # Compare against the counts the independent computation derived from the format
  # declaration, not against a divisibility rule. `children %% parents == 0` also
  # holds for one parent with two children, so it cannot tell a full format domain
  # from one whose zero-count nodes were dropped -- and a dropped node has no cell
  # to disagree with, which is what makes this check necessary at all.
  want <- c(parents = expected_shape$parents, zero_parents = expected_shape$zero_parents,
            children = expected_shape$children, zero_children = expected_shape$zero_children,
            non_zero = expected_shape$non_zero)
  list(
    table = table,
    parents = actual[["parents"]],
    children = actual[["children"]],
    zero_parents = actual[["zero_parents"]],
    zero_children = actual[["zero_children"]],
    non_zero = actual[["non_zero"]],
    agrees = identical(unname(actual), unname(want))
  )
}

# Pagination is a layout contract with no numeric signal: a broken page break
# still produces the right numbers. The paginated rows are the only artifact that
# carries page_group, so the invariant is checked there. Capacity counts printed
# lines, so a page holds at most page_rows of them; the page-edge blanks are
# mandatory, so every page must open and close with a spacer, and a block
# separator must never be the last body row.
check_pagination <- function(table, page_rows) {
  path <- file.path(sas_dir, paste0("paged_", table, ".sas7bdat"))
  if (!file.exists(path)) {
    stop("Missing paginated SAS output: ", path, call. = FALSE)
  }
  data <- haven::read_sas(path)
  # The dataset is already sorted by the page key (page_group, edge, report_order)
  # and the page-edge pads carry no report_order at all, so re-sorting here by
  # report_order would push them to the end and report a phantom violation.
  # Physical row order is the contract.
  role <- as.character(data$row_role)
  groups <- data$page_group
  sizes <- tapply(rep(1L, nrow(data)), groups, sum)
  first_blank <- tapply(role, groups, function(x) x[[1L]] == "spacer")
  last_blank <- tapply(role, groups, function(x) x[[length(x)]] == "spacer")
  # A block separator belongs to the block after it, so it can never be the last
  # body row of a page. The page's own bottom pad always follows it, so two
  # consecutive blanks at the end mean a separator was stranded at the page edge.
  double_trailing_blank <- tapply(role, groups, function(x) {
    length(x) >= 2L && x[[length(x)]] == "spacer" && x[[length(x) - 1L]] == "spacer"
  })
  list(
    table = table,
    pages = length(unique(groups)),
    rows = nrow(data),
    largest_page = max(sizes),
    capacity = page_rows,
    oversized = sum(sizes > page_rows),
    missing_first_blank = sum(!first_blank),
    missing_last_blank = sum(!last_blank),
    stranded_separator = sum(double_trailing_blank)
  )
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
  # One definition of the path, shared with check_node_order().
  node_paths <- report_paths(data$label, data$hierarchy_level, data$row_role)
  for (i in seq_len(nrow(data))) {
    label <- data$label[[i]]
    level <- data$hierarchy_level[[i]]
    if (!is.na(level) && level > 0L) {
      # A node row, or a below row that keeps the node path and appends its label.
      path <- node_paths[[i]]
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

calculate_status <- function(expected_rows, actual_rows, table) {
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
  outcome <- calculate_status(expected_rows, actual_rows, table)
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

# The bundle is read once here and reused for two things: it decides which tables
# have a format-driven level (see the registration check below) and it supplies
# each header's page capacity. Sourcing the codec is cheap and keeps the numbers
# from drifting out of sync with the metadata.
dummy_bundle <- local({
  source(file.path("src", "metadata", "model.R"))
  source(file.path("src", "metadata", "yaml_codec.R"))
  bundle_dir <- file.path("dummy_study", "metadata")
  read_entry <- function(path) {
    text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    parse_yaml_document_text(text)$value
  }
  entry_files <- function(directory, pattern = "[.]yaml$") {
    sort(list.files(file.path(bundle_dir, directory), pattern = pattern, full.names = TRUE))
  }
  list(
    headers = local({
      manifest <- entry_files(".")
      parsed <- lapply(manifest, read_entry)
      hit <- Filter(function(entry) !is.null(entry$headers), parsed)
      if (length(hit) == 0L) list() else hit[[1L]]$headers
    }),
    templates = lapply(entry_files("templates"), read_entry),
    tables = lapply(entry_files("tables"), read_entry)
  )
})

source_page_rows_default <- function() {
  if (exists("default_page_rows", inherits = TRUE)) default_page_rows else 22L
}

table_header_by_id <- function(table_id) {
  table <- Filter(function(entry) identical(as.character(entry$id), as.character(table_id)),
                  dummy_bundle$tables)
  if (length(table) == 0L) return(NULL)
  headers <- Filter(function(header) {
    identical(as.character(header$id), as.character(table[[1L]]$header_id))
  }, dummy_bundle$headers)
  if (length(headers) == 0L) NULL else headers[[1L]]
}

# Pagination is checked after the numbers, because a layout regression must not
# be able to mask a statistical one. The capacity lives on each table's header,
# not here: a hard-coded number would silently stop checking anything on the day
# a header sets its own page_rows.
default_page_rows <- source_page_rows_default()
page_capacity_for <- function(table) {
  header <- table_header_by_id(table)
  if (is.null(header) || is.null(header$page_rows)) default_page_rows else header$page_rows
}
# A header that cannot be resolved would fall back to the default and silently
# stop checking the real setting, so prove resolution first.
unresolved <- Filter(function(table) is.null(table_header_by_id(table)),
                     unique(expected$table))
if (length(unresolved) > 0L) {
  cat(sprintf("
no header resolved for table(s): %s
",
              paste(unresolved, collapse = ", ")))
  quit(status = 1L)
}
pagination <- lapply(unique(expected$table), function(table) {
  check_pagination(table, page_rows = page_capacity_for(table))
})
pagination <- do.call(rbind, lapply(pagination, as.data.frame,
                                   stringsAsFactors = FALSE))
cat(sprintf("\n%-30s %5s %5s %8s %9s\n", "pagination", "pages", "rows",
            "largest", "capacity"))
for (i in seq_len(nrow(pagination))) {
  row <- pagination[i, ]
  cat(sprintf("%-30s %5d %5d %8d %9d\n", row$table, row$pages, row$rows,
              row$largest_page, row$capacity))
}
pagination_broken <- pagination[pagination$oversized > 0L |
                                pagination$missing_first_blank > 0L |
                                pagination$missing_last_blank > 0L |
                                pagination$stranded_separator > 0L, , drop = FALSE]
if (nrow(pagination_broken) > 0L) {
  cat("\npagination contract violated: a page overflowed, lost an edge blank, ",
      "or stranded a block separator at the page edge\n", sep = "")
  print(pagination_broken)
  quit(status = 1L)
}
cat(sprintf("%d pages across %d tables; every page within capacity and padded\n",
            sum(pagination$pages), nrow(pagination)))

# Zero-count format nodes must be printed, which no cell comparison can observe.
# A table with a format-driven level is only covered once compute_expected.R has
# written its expected node shape, and that registration used to be a convention
# nobody enforced: adding a format table and forgetting the entry silently left
# the whole contract untested. Fail on the gap instead.
format_level_tables <- local({
  has_format <- vapply(dummy_bundle$templates, function(template) {
    chunks <- template$body$chunks %||% list()
    any(vapply(chunks, function(chunk) {
      any(vapply(chunk$levels %||% list(), function(level) !is.null(level$format),
                 logical(1L)))
    }, logical(1L)))
  }, logical(1L))
  format_template_ids <- vapply(dummy_bundle$templates[has_format],
                                function(template) template$id, character(1L))
  vapply(dummy_bundle$tables, function(table) table$id, character(1L))[
    vapply(dummy_bundle$tables, function(table) table$template_id, character(1L)) %in%
      format_template_ids
  ]
})
format_shapes <- utils::read.csv(file.path("dummy_study", "generated", "expected",
                                           "node_shape.csv"), stringsAsFactors = FALSE)
unregistered <- setdiff(format_level_tables, format_shapes$table)
if (length(unregistered) > 0L) {
  cat(sprintf("\nformat-driven table missing from node_shape.csv: %s\n",
              paste(unregistered, collapse = ", ")))
  cat("Every table with a format-driven level needs an expected node shape, or its\n")
  cat("zero-count nodes print unchecked. Add it to compute_expected.R.\n")
  quit(status = 1L)
}
format_checks <- Filter(Negate(is.null), lapply(seq_len(nrow(format_shapes)), function(i) {
  check_format_nodes(format_shapes$table[[i]], format_shapes[i, , drop = FALSE])
}))
if (length(format_checks) > 0L) {
  cat("\nformat-driven nodes (zero-count nodes are printed, not dropped)\n")
  for (check in format_checks) {
    cat(sprintf("%-30s %2d parents (%2d zero)  %3d children (%3d zero)  non-zero rows %d\n",
                check$table, check$parents, check$zero_parents,
                check$children, check$zero_children, check$non_zero))
  }
  violated <- !vapply(format_checks, `[[`, logical(1L), "agrees")
  if (any(violated)) {
    cat("\nformat node shape violated: the printed node counts do not match the format domain\n")
    quit(status = 1L)
  }
}
