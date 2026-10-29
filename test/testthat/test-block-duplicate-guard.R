guard_by_lines <- function(source) {
  lines <- strsplit(source, "\n", fixed = TRUE)[[1]]
  starts <- grep("out=_TFL_GUARD_", lines)
  if (!length(starts)) return(character())
  vapply(starts, function(index) {
    hit <- grep("^  by ", lines[index:min(index + 2L, length(lines))], value = TRUE)
    if (!length(hit)) NA_character_ else trimws(hit[[1L]])
  }, character(1L))
}

base_bundle <- function(chunk) {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "all", label = "All", condition = "1", display_order = 1L,
                               width = 1, alignment = "center")
                        ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(chunk))))
  )
}

categorical_chunk <- function(unit, distinct_key = NULL) {
  chunk <- list(
    id = "sex", type = "categorical_summary_nonexclusive", source_data = "adam.adsl",
    counting_unit = unit,
    denominator = list(type = "header_population"),
    rows = list(list(
      id = "female", type = "analysis", label = "Female", condition = "SEX = 'F'",
      statistics = list(list(id = "n")), cell_format = "{n}"
    ))
  )
  if (!is.null(distinct_key)) chunk$distinct_key <- distinct_key
  chunk
}

continuous_chunk <- function(unit, distinct_key = NULL) {
  chunk <- list(
    id = "age", type = "continuous_summary", source_data = "adam.adsl",
    counting_unit = unit, analysis_variable = "AGE",
    rows = list(list(
      id = "r1", type = "analysis", label = "Age",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ))
  )
  if (!is.null(distinct_key)) chunk$distinct_key <- distinct_key
  chunk
}

testthat::test_that("record counting emits no duplicate guard and no source key table", {
  for (chunk in list(categorical_chunk("record"), continuous_chunk("record"))) {
    result <- generate_table_source(base_bundle(chunk), "t1", include_duplicate_check = TRUE)
    testthat::expect_true(result$passed)
    testthat::expect_length(guard_by_lines(result$source), 0L)
    testthat::expect_false(grepl("duplicate_key", result$source, fixed = TRUE))
    testthat::expect_false(grepl("_TFL_KKEY_", result$source, fixed = TRUE))
  }
})

testthat::test_that("distinct-subject counting guards the subject key per block", {
  categorical <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                      include_duplicate_check = TRUE)
  continuous <- generate_table_source(base_bundle(continuous_chunk("distinct_subject")), "t1",
                                      include_duplicate_check = TRUE)
  testthat::expect_equal(guard_by_lines(categorical$source), "by chunk_order USUBJID;")
  testthat::expect_equal(guard_by_lines(continuous$source), "by chunk_order USUBJID;")
})

testthat::test_that("distinct-key counting guards the declared key per block", {
  keys <- c("USUBJID", "VISIT")
  categorical <- generate_table_source(
    base_bundle(categorical_chunk("distinct_key", keys)), "t1", include_duplicate_check = TRUE)
  continuous <- generate_table_source(
    base_bundle(continuous_chunk("distinct_key", keys)), "t1", include_duplicate_check = TRUE)
  expected <- "by chunk_order USUBJID VISIT;"
  testthat::expect_equal(guard_by_lines(categorical$source), expected)
  testthat::expect_equal(guard_by_lines(continuous$source), expected)
})

testthat::test_that("per-block guards omit column_order while dedup keys keep it", {
  result <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                  include_duplicate_check = TRUE)
  testthat::expect_false(grepl("column_order", paste(guard_by_lines(result$source),
                                                     collapse = " "), fixed = TRUE))
  # Header expansion would otherwise report one source duplicate once per column.
  testthat::expect_match(result$source,
                         "by chunk_order column_order node_key USUBJID;", fixed = TRUE)
})

testthat::test_that("duplicate checking can be switched off entirely", {
  result <- generate_table_source(base_bundle(categorical_chunk("distinct_subject")), "t1",
                                  include_duplicate_check = FALSE)
  testthat::expect_length(guard_by_lines(result$source), 0L)
  testthat::expect_false(grepl("duplicate_key", result$source, fixed = TRUE))
})

# --- Regressions found in review of the counting-unit change -----------------

# Return the keep lists of every DATA step in a generated program, keyed by the
# dataset each step writes.
keep_lists <- function(lines) {
  # A keep list may wrap across lines, so join continuations until the
  # terminating semicolon before splitting it into variable names.
  starts <- grep("^data [A-Z0-9_]+;", lines)
  out <- list()
  for (start in starts) {
    written <- sub("^data ([A-Z0-9_]+);", "\\1", lines[start])
    rest <- lines[(start + 1L):length(lines)]
    stop_at <- which(rest == "run;")[1L]
    body <- rest[seq_len(stop_at)]
    keep_at <- grep("^  keep ", body)
    vars <- character()
    for (at in keep_at) {
      text <- body[at]
      while (!grepl(";", text, fixed = TRUE) && at < length(body)) {
        at <- at + 1L
        text <- paste(text, body[at])
      }
      text <- sub("^  keep ", "", text)
      text <- gsub(";", "", text, fixed = TRUE)
      vars <- c(vars, strsplit(trimws(text), " ", fixed = TRUE)[[1L]])
    }
    out[[written]] <- unique(vars[nzchar(vars)])
  }
  out
}

# Pull `data=<name>` out of a `proc sort data=<name> out=...;` line.
sorted_input <- function(line) {
  token <- strsplit(trimws(line), " ", fixed = TRUE)[[1L]][3L]
  sub("^data=", "", sub("\\).*$", "", token))
}

testthat::test_that("every guard BY variable is produced by its input dataset", {
  # A guard sorting on a variable its input never kept generates invalid SAS
  # immediately, before any duplicate data is needed to trigger it.
  for (chunk in list(continuous_chunk("distinct_subject"),
                     continuous_chunk("distinct_key", c("USUBJID", "VISIT")),
                     categorical_chunk("distinct_subject"),
                     categorical_chunk("distinct_key", c("USUBJID", "VISIT")))) {
    result <- generate_table_source(base_bundle(chunk), "t1", include_duplicate_check = TRUE)
    testthat::expect_true(result$passed)
    lines <- strsplit(result$source, "\n", fixed = TRUE)[[1]]
    keeps <- keep_lists(lines)
    for (start in grep("out=_TFL_GUARD_", lines)) {
      input_dataset <- sorted_input(lines[start])
      by_line <- grep("^  by ", lines[start:min(start + 2L, length(lines))], value = TRUE)[[1L]]
      by_vars <- strsplit(trimws(gsub(";", "", sub("^  by ", "", by_line), fixed = TRUE)), " ", fixed = TRUE)[[1L]]
      testthat::expect_true(input_dataset %in% names(keeps), info = input_dataset)
      for (key in by_vars) {
        testthat::expect_true(key %in% keeps[[input_dataset]],
                              info = paste(input_dataset, "keeps", key))
      }
    }
  }
})

testthat::test_that("record counting keeps one row per source record", {
  # An empty identity key used to make NODUPKEY collapse the whole table, which
  # silently reported 1 instead of n for record counting.
  result <- generate_table_source(base_bundle(categorical_chunk("record")), "t1",
                                  include_duplicate_check = TRUE)
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source,
                         "by chunk_order column_order node_key row_order source_row;",
                         fixed = TRUE)
  # record emits no duplicate check, but still must not collapse records.
  testthat::expect_length(guard_by_lines(result$source), 0L)
})

testthat::test_that("exclusive guard never sorts on an empty key", {
  chunk <- categorical_chunk("record")
  chunk$type <- "categorical_summary_exclusive"
  result <- generate_table_source(base_bundle(chunk), "t1", include_duplicate_check = TRUE)
  testthat::expect_true(result$passed)
  # An empty last key produced the invalid statement `if first. then do;`.
  testthat::expect_false(grepl("if first. ", result$source, fixed = TRUE))
  testthat::expect_false(grepl("if last. ", result$source, fixed = TRUE))
  testthat::expect_match(result$source, "if first.source_row then do;", fixed = TRUE)
})

testthat::test_that("top-level continuous honours distinct counting units", {
  # Top-level chunks used to skip unit materialization entirely, so
  # distinct_subject let every source record reach PROC MEANS.
  result <- generate_table_source(base_bundle(continuous_chunk("distinct_subject")), "t1",
                                  include_duplicate_check = FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "data _TFL_CUNIT_001;", fixed = TRUE)
  testthat::expect_match(result$source, "proc means data=_TFL_CUNIT_001", fixed = TRUE)
  testthat::expect_false(grepl("proc means data=_TFL_CIN_001", result$source, fixed = TRUE))

  keyed <- generate_table_source(
    base_bundle(continuous_chunk("distinct_key", c("USUBJID", "VISIT"))), "t1",
    include_duplicate_check = FALSE)
  testthat::expect_true(keyed$passed)
  testthat::expect_match(keyed$source, "by chunk_order column_order node_key USUBJID VISIT;",
                         fixed = TRUE)
})

testthat::test_that("declared distinct keys reach the categorical analysis input", {
  result <- generate_table_source(
    base_bundle(categorical_chunk("distinct_key", c("USUBJID", "VISIT"))), "t1",
    include_duplicate_check = FALSE)
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1]]
  keeps <- keep_lists(lines)
  # The membership join must carry VISIT rather than dropping it, otherwise the
  # numerator and denominator sorts reference a variable that does not exist.
  testthat::expect_true(any(grepl("^         , s.VISIT$", lines)))
  testthat::expect_true("VISIT" %in% keeps[["_TFL_KIN_001"]])
  by_visit <- Filter(function(x) "VISIT" %in% strsplit(trimws(gsub(";", "", sub("^  by ", "", x), fixed = TRUE)), " ")[[1L]],
                     grep("^  by ", lines, value = TRUE))
  testthat::expect_true(length(by_visit) > 0L)
})

testthat::test_that("guards run on source records, not on expanded copies", {
  # One source record matched by two header columns used to be reported as a
  # duplicate, because the guard ran after the membership join had broadcast it.
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "a", label = "A", condition = "1", display_order = 1L,
                               width = 1, alignment = "center"),
                          list(id = "b", label = "B", condition = "1", display_order = 2L,
                               width = 1, alignment = "center")))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(categorical_chunk("distinct_subject")))))
  )
  result <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1]]
  guard_start <- grep("out=_TFL_GUARD_", lines)
  testthat::expect_length(guard_start, 1L)
  guarded <- sorted_input(lines[guard_start])
  # The guarded dataset must be the pre-expansion source projection: a table
  # carrying column_order would mean the guard sees one row per header column.
  testthat::expect_match(guarded, "_TFL_KSRC_", fixed = TRUE)
  keeps <- keep_lists(lines)
  testthat::expect_false("column_order" %in% keeps[[guarded]])
  testthat::expect_false("row_order" %in% keeps[[guarded]])
})
