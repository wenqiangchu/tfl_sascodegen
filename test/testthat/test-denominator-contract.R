denominator_bundle <- function(denominator, nested = FALSE,
                               numerator_unit = "distinct_subject",
                               numerator_key = NULL) {
  analysis <- list(
    id = "a", type = "categorical_summary_nonexclusive",
    counting_unit = numerator_unit, denominator = denominator,
    rows = list(list(id = "r", type = "analysis", label = "Severe",
                     condition = "AESEVN = 3", statistics = list(
                       list(id = "n"), list(id = "pct", digits = 1L)),
                     cell_format = "{n} ({pct}%)"))
  )
  if (!is.null(numerator_key)) analysis$distinct_key <- numerator_key
  if (nested) {
    analysis$anchor_level <- "soc"
    analysis$placement <- "below"
    chunk <- list(id = "ae", type = "hierarchical_summary",
                  source_data = "adam.adae", filter = "TRTEMFL = 'Y'",
                  levels = list(list(id = "soc", variable = "SOC",
                                     order_variable = "SOCN", order_direction = "asc",
                                     node_role = "label", missing_policy = "exclude")),
                  analysis_blocks = list(analysis))
  } else {
    chunk <- analysis
    chunk$source_data <- "adam.adae"
    chunk$filter <- "TRTEMFL = 'Y'"
  }
  new_metadata_bundle(
    schema_version = 2L,
    populations = list(list(id = "p", label = "Safety", expression = "SAFFL = 'Y'")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "drug", label = "Drug", condition = "TRT01AN = 1",
                               display_order = 1L, width = 1, alignment = "center"),
                          list(id = "all", label = "All", condition = "1",
                               display_order = 2L, width = 1, alignment = "center")))),
    tables = list(list(id = "t", population_id = "p", header_id = "h", template_id = "tpl")),
    templates = list(list(id = "tpl", body = list(chunks = list(chunk))))
  )
}

denominator_generated <- function(denominator, nested = FALSE,
                                  numerator_unit = "distinct_subject", numerator_key = NULL) {
  result <- generate_table_source(denominator_bundle(denominator, nested,
                                                    numerator_unit, numerator_key), "t",
                                  include_duplicate_check = FALSE)
  testthat::expect_true(result$passed, info = paste(vapply(result$errors, `[[`, "", "message"),
                                                  collapse = "\n"))
  result$source
}

# Inspect a complete generated DATA step, so qualification and grouping are
# checked in the same producer rather than by unrelated substring matches.
denominator_step <- function(source, dataset) {
  pattern <- paste0("(?s)data ", dataset, ";\\n(.*?)\\nrun;")
  matched <- regmatches(source, regexec(pattern, source, perl = TRUE))[[1L]]
  testthat::expect_length(matched, 2L)
  if (length(matched) < 2L) return("")
  matched[[2L]]
}

testthat::test_that("v2 round trips independent denominator keys and rejects v1", {
  den <- list(scope = "chunk_source", unit = "distinct_key",
              expression = "EVALFL = 'Y'\nand not missing(CYCLE)",
              distinct_key = c("USUBJID", "CYCLE"))
  bundle <- denominator_bundle(den, numerator_unit = "distinct_key",
                               numerator_key = c("USUBJID", "AESEQ"))
  parsed <- parse_bundle_value(bundle)
  testthat::expect_length(parsed$errors, 0L)
  bytes <- canonical_archive_bytes(bundle)
  second <- parse_bundle_archive(bytes)
  testthat::expect_true(second$passed)
  actual <- second$workspace$templates[[1L]]$body$chunks[[1L]]
  testthat::expect_identical(actual$denominator, den)
  testthat::expect_identical(actual$distinct_key, c("USUBJID", "AESEQ"))
  testthat::expect_identical(second$workspace$schema_version, 2L)
  testthat::expect_identical(bytes$bytes, canonical_archive_bytes(second$workspace)$bytes)
  bundle$schema_version <- 1L
  old <- parse_bundle_value(bundle)
  testthat::expect_true("bundle_schema_unsupported" %in% vapply(old$errors, `[[`, "", "code"))
  manifest <- parse_manifest_yaml("schema_version: 1\n")
  testthat::expect_identical(manifest$errors[[1L]]$code, "bundle_schema_unsupported")
})

testthat::test_that("denominator structure enforces its own key and valid host scopes", {
  invalid <- list(
    list(scope = "chunk_source", unit = "distinct_key"),
    list(scope = "chunk_source", unit = "distinct_subject", distinct_key = "CYCLE"),
    list(scope = "header_population", unit = "record"),
    list(scope = "current_group", unit = "distinct_subject"),
    list(scope = "chunk_source", unit = "record", expression = ""),
    list(scope = "chunk_source", unit = "distinct_key", distinct_key = c("CYCLE", "CYCLE")),
    list(type = "non_missing", variable = "AESEVN")
  )
  for (den in invalid) {
    parsed <- parse_bundle_value(denominator_bundle(den, numerator_unit = "distinct_key",
                                                    numerator_key = c("USUBJID", "AESEQ")))
    testthat::expect_gt(length(parsed$errors), 0L)
    testthat::expect_null(parsed$value)
  }
  valid <- parse_bundle_value(denominator_bundle(
    list(scope = "current_group", unit = "distinct_key", distinct_key = "CYCLE"), nested = TRUE))
  testthat::expect_length(valid$errors, 0L)
})

testthat::test_that("header qualification uses retained header variables before subject dedup", {
  source <- denominator_generated(list(scope = "header_population", unit = "distinct_subject",
                                      expression = "EVALFL = 'Y'"))
  qualified <- denominator_step(source, "_TFL_KDQUAL_001_001")
  testthat::expect_match(qualified, "set _TFL_POP_001;", fixed = TRUE)
  testthat::expect_match(qualified,
    "if (TRT01AN = 1) and (EVALFL = 'Y') then do; column_order = 1; output; end;",
    fixed = TRUE)
  testthat::expect_match(qualified, "column_order = 2;", fixed = TRUE)
  testthat::expect_lt(regexpr("EVALFL", qualified)[[1L]], regexpr("keep ", qualified)[[1L]])
  testthat::expect_match(source,
    "proc sort data=_TFL_KDQUAL_001_001 out=_TFL_KDUNIT_001_001 nodupkey;\n  by column_order USUBJID;",
    fixed = TRUE)
  testthat::expect_false(grepl("EVALFL", denominator_step(source, "_TFL_MEM_001"), fixed = TRUE))
  testthat::expect_false(grepl("EVALFL", denominator_step(source, "_TFL_KPRE_001_001"), fixed = TRUE))
  map <- build_logical_result_map(denominator_bundle(
    list(scope = "header_population", unit = "distinct_subject", expression = "EVALFL = 'Y'"))$
      templates[[1L]]$body$chunks[[1L]], 1L, list(list(id = "all")))
  testthat::expect_true(all(vapply(map, `[[`, integer(1L), "use_header_n") == 0L))
})

testthat::test_that("independent denominator keys are qualified outside numerator events", {
  source <- denominator_generated(list(scope = "chunk_source", unit = "distinct_key",
                                      expression = "EVALFL = 'Y'", distinct_key = "CYCLE"))
  testthat::expect_match(source, "from _TFL_KSRC_001_001 as s inner join _TFL_MEM_001 as m",
                        fixed = TRUE)
  qualified <- denominator_step(source, "_TFL_KDQUAL_001_001")
  testthat::expect_match(qualified, "EVALFL = 'Y'", fixed = TRUE)
  testthat::expect_match(qualified, "keep column_order CYCLE;", fixed = TRUE)
  testthat::expect_match(source, "by column_order CYCLE;", fixed = TRUE)
  testthat::expect_false(grepl("CYCLE|EVALFL", denominator_step(source, "_TFL_KPRE_001_001")))
  testthat::expect_match(source, "by chunk_order column_order node_key row_order USUBJID;", fixed = TRUE)
})

testthat::test_that("record denominators use only real source observations", {
  source <- denominator_generated(list(scope = "chunk_source", unit = "record"))
  testthat::expect_match(source, "inner join _TFL_MEM_001", fixed = TRUE)
  testthat::expect_false(grepl("out=_TFL_KDUNIT_001_001 nodupkey", source, fixed = TRUE))
  testthat::expect_false(grepl("union all", source, fixed = TRUE))
  testthat::expect_match(denominator_step(source, "_TFL_KDEN_001_001"),
                        "set _TFL_KDQUAL_001_001;", fixed = TRUE)
})

testthat::test_that("nested chunk and current-group denominators keep different scopes", {
  global <- denominator_generated(list(scope = "chunk_source", unit = "record"), nested = TRUE)
  local <- denominator_generated(list(scope = "current_group", unit = "record"), nested = TRUE)
  testthat::expect_match(global, "from _TFL_HSRC_001 as s inner join _TFL_HMEM_001 as m", fixed = TRUE)
  testthat::expect_match(denominator_step(global, "_TFL_KDEN_002_001"), "node_key = '';", fixed = TRUE)
  testthat::expect_match(global, "and d.node_key = ''", fixed = TRUE)
  testthat::expect_match(denominator_step(local, "_TFL_KDQUAL_002_001"),
                        "set _TFL_HMERGE_001_001;", fixed = TRUE)
  testthat::expect_match(local, "and k.node_key = d.node_key", fixed = TRUE)
  testthat::expect_false(grepl("node_key = '';", denominator_step(local, "_TFL_KDEN_002_001"), fixed = TRUE))
})

testthat::test_that("compatible chunks keep different denominator conditions within one MEANS", {
  bundle <- denominator_bundle(list(scope = "chunk_source", unit = "distinct_subject",
                                    expression = "EVALFL = 'Y'"))
  other <- bundle$templates[[1L]]$body$chunks[[1L]]
  other$id <- "other"
  other$denominator$expression <- "ANL01FL = 'Y'"
  bundle$templates[[1L]]$body$chunks[[2L]] <- other
  generated <- generate_table_source(bundle, "t", include_duplicate_check = FALSE)
  testthat::expect_true(generated$passed)
  source <- generated$source
  testthat::expect_length(gregexpr("proc means ", source, fixed = TRUE)[[1L]], 1L)
  testthat::expect_match(denominator_step(source, "_TFL_KDQUAL_001_001"), "EVALFL = 'Y'", fixed = TRUE)
  testthat::expect_match(denominator_step(source, "_TFL_KDQUAL_001_002"), "ANL01FL = 'Y'", fixed = TRUE)
  testthat::expect_match(source, "set _TFL_KDEN_001_001 _TFL_KDEN_001_002 _TFL_KNUM_001;", fixed = TRUE)
  testthat::expect_match(source, "else pct = .;", fixed = TRUE)
  testthat::expect_false(grepl("numerator = 0", source, fixed = TRUE))
})
