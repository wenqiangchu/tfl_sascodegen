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

# Return the variables each DATA step exposes, keyed by the dataset it writes.
# A step without a keep list inherits every variable from the datasets it
# reads via SET, which is how _TFL_CPRE_* passes the chunk input through.
keep_lists <- function(lines) {
  starts <- grep("^data [A-Z0-9_]+;", lines)
  steps <- list()
  order <- character()
  for (start in starts) {
    written <- sub("^data ([A-Z0-9_]+);", "\\1", lines[start])
    rest <- lines[(start + 1L):length(lines)]
    stop_at <- which(rest == "run;")[1L]
    body <- rest[seq_len(stop_at)]
    keep_at <- grep("^  keep ", body)
    vars <- character()
    if (length(keep_at)) {
      for (at in keep_at) {
        text <- body[at]
        while (!grepl(";", text, fixed = TRUE) && at < length(body)) {
          at <- at + 1L
          text <- paste(text, body[at])
        }
        text <- gsub(";", "", sub("^  keep ", "", text), fixed = TRUE)
        vars <- c(vars, strsplit(trimws(text), " ", fixed = TRUE)[[1L]])
      }
    } else {
      reads <- grep("^  set ", body, value = TRUE)
      for (read in reads) {
        text <- gsub(";", "", sub("^  set ", "", read), fixed = TRUE)
        for (source in strsplit(trimws(text), " ", fixed = TRUE)[[1L]]) {
          vars <- c(vars, steps[[source]])
        }
      }
    }
    steps[[written]] <- unique(vars[nzchar(vars)])
    order <- c(order, written)
  }
  steps
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

testthat::test_that("continuous guards also run before the membership join", {
  # The same broadcast problem applied here: the guard used to sort _TFL_CIN_*,
  # which already has one row per source record per header column.
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "a", label = "A", condition = "1", display_order = 1L,
                               width = 1, alignment = "center"),
                          list(id = "b", label = "B", condition = "1", display_order = 2L,
                               width = 1, alignment = "center")))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(continuous_chunk("distinct_subject")))))
  )
  result <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1]]
  guard_start <- grep("out=_TFL_GUARD_", lines)
  testthat::expect_length(guard_start, 1L)
  guarded <- sorted_input(lines[guard_start])
  testthat::expect_match(guarded, "_TFL_CPRE_", fixed = TRUE)
  keeps <- keep_lists(lines)
  testthat::expect_false("column_order" %in% keeps[[guarded]])
  testthat::expect_true("USUBJID" %in% keeps[[guarded]])
})


# Pull the BY variables out of the sort that feeds a guard.
keep_by_vars <- function(lines, guard_start) {
  # The sort statement sits inside the next few lines after the guard header.
  hit <- grep("^  by ", lines[guard_start:min(guard_start + 4L, length(lines))],
              value = TRUE)
  testthat::expect_length(hit, 1L)
  vars <- strsplit(trimws(sub(";$", "", hit[[1L]])), " ", fixed = TRUE)[[1L]]
  vars[-1L]
}
nested_continuous_duplicate_fixture <- function(unit = "distinct_subject", distinct_key = NULL) {
  # A minimal nested continuous batch: one hierarchy level anchors one block, so
  # the block runs against a node-scoped level table rather than the top level.
  block <- list(
    id = "a1", anchor_level = "l1", placement = "below",
    type = "continuous_summary", counting_unit = unit,
    analysis_variable = "AGE",
    rows = list(list(id = "r1", type = "analysis", label = "Mean",
                     statistics = list(list(id = "mean", digits = 1L)),
                     cell_format = "{mean}"))
  )
  if (!is.null(distinct_key)) block$distinct_key <- distinct_key
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(list(id = "all", label = "All", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(list(
      id = "hier", type = "hierarchical_summary", source_data = "adam.adae",
      filter = "SAFFL = 'Y'",
      levels = list(
        list(id = "l1", variable = "SOC", order_variable = "SOCN",
             order_direction = "asc", node_role = "label", missing_policy = "exclude"),
        list(id = "l2", variable = "PT", order_variable = "PTN",
             order_direction = "asc", node_role = "label", missing_policy = "exclude")
      ),
      analysis_blocks = list(block)
    )))))
  )
}

testthat::test_that("nested categorical guards read the node level table", {
  # The hierarchical membership join broadcasts each level record across header
  # columns, so a guard on the merged source would count broadcast copies.
  path <- file.path(project_root, "assets", "demo_metadata.zip")
  skip_if_not(file.exists(path), "demo bundle is not available")
  imported <- application_import_bundle(
    new_empty_workspace(), readBin(path, "raw", n = file.info(path)$size))
  testthat::expect_true(imported$passed)
  generated <- application_generate_source(imported$workspace, "ae_by_soc_pt",
                                           include_duplicate_check = TRUE)
  testthat::expect_true(generated$passed)
  lines <- strsplit(generated$value, "\n", fixed = TRUE)[[1]]
  guard_start <- grep("out=_TFL_GUARD_", lines)
  testthat::expect_length(guard_start, 1L)
  guarded <- sorted_input(lines[guard_start])
  # The guard must not read a table that carries one row per header column.
  testthat::expect_false("column_order" %in% keep_lists(lines)[[guarded]])
  # The guard input is built by a DATA step, so the level table reaches it
  # through that step rather than by being sorted directly.
  build <- grep(paste0("^data ", guarded, ";$"), lines)
  testthat::expect_length(build, 1L)
  feeder <- grep("^  set _TFL_", lines[build:min(build + 4L, length(lines))],
                 value = TRUE)
  testthat::expect_length(feeder, 1L)
  testthat::expect_false(grepl("HMERGE|KMERGE|CPRE|CMERGE", feeder[[1L]]))
})

testthat::test_that("nested continuous guards construct the chunk position field", {
  # A nested level table has no chunk_order, so sorting it by chunk_order without
  # constructing the field references a variable that does not exist.
  for (unit in c("distinct_subject", "distinct_key")) {
    bundle <- nested_continuous_duplicate_fixture(
      unit, if (unit == "distinct_key") c("USUBJID", "AESEQ") else NULL)
    generated <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
    testthat::expect_true(generated$passed)
    lines <- strsplit(generated$source, "\n", fixed = TRUE)[[1]]
    guard_start <- grep("out=_TFL_GUARD_", lines)
    testthat::expect_length(guard_start, 1L)
    guarded <- sorted_input(lines[guard_start])
    by_vars <- keep_by_vars(lines, guard_start)
    # Every sorted variable has to exist in the guard input.
    available <- keep_lists(lines)[[guarded]]
    testthat::expect_false(is.null(available))
    testthat::expect_true(all(by_vars %in% available))
    # The level table never carries chunk_order, so the guard input must be built
    # by a DATA step that assigns it explicitly.
    build <- grep(paste0("^data ", guarded, ";$"), lines)
    testthat::expect_length(build, 1L)
    body <- lines[build:min(build + 6L, length(lines))]
    testthat::expect_true(any(grepl("^  chunk_order = ", body)))
  }
})

testthat::test_that("nested record counting emits no duplicate guard", {
  bundle <- nested_continuous_duplicate_fixture("record")
  generated <- generate_table_source(bundle, "t1", include_duplicate_check = TRUE)
  testthat::expect_true(generated$passed)
  testthat::expect_false(grepl("out=_TFL_GUARD_", generated$source, fixed = TRUE))
})
testthat::test_that("declared keys reach both branches of the membership union", {
  # The scaffold branch supplies denominator rows for a header-population chunk.
  # It runs through the same UNION ALL as the event branch, so it has to carry
  # every declared distinct key as well; otherwise the two branches disagree on
  # column count and SAS cannot build the merged table at all.
  for (check in c(TRUE, FALSE)) {
    chunk <- categorical_chunk("distinct_key", c("USUBJID", "VISIT"))
    chunk$denominator <- list(type = "header_population")
    result <- generate_table_source(base_bundle(chunk), "t1",
                                    include_duplicate_check = check)
    testthat::expect_true(result$passed)
    lines <- strsplit(result$source, "\n", fixed = TRUE)[[1]]
    union_at <- grep("^  union all$", lines)
    testthat::expect_length(union_at, 1L)
    event_at <- max(grep("^  select ", lines[seq_len(union_at)]))
    scaffold_at <- union_at + grep("^  select ", lines[union_at:length(lines)])[1L]
    # Count the projected columns by the continuation lines that add keys.
    event_cols <- length(grep("^         , s\\.", lines[event_at:union_at]))
    scaffold_cols <- length(grep("^         , t\\.", lines[scaffold_at:length(lines)][1:5]))
    testthat::expect_equal(scaffold_cols, event_cols)
    testthat::expect_gt(scaffold_cols, 0L)
    # Both branches name the same key, so the merged table keeps one column.
    event_side <- paste(lines[event_at:union_at], collapse = " ")
    scaffold_side <- paste(lines[scaffold_at:length(lines)], collapse = " ")
    testthat::expect_match(event_side, "s.VISIT", fixed = TRUE)
    testthat::expect_match(scaffold_side, "t.VISIT", fixed = TRUE)
  }
})
