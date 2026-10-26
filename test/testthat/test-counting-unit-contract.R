# Counting-unit declarations are the single source of counting semantics for
# analysis chunks. These assertions pin the contract shared by primitive chunks
# and hierarchical analysis blocks so the two hosts cannot drift apart.

counting_unit_chunk <- function(overrides = list()) {
  chunk <- list(
    id = "c1", type = "continuous_summary", source_data = "adam.adsl",
    counting_unit = "distinct_subject", analysis_variable = "AGE",
    rows = list(list(
      id = "r1", type = "analysis", label = "Mean",
      statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
    ))
  )
  modifyList(chunk, overrides)
}

counting_unit_bundle <- function(chunk) {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "P", expression = "1")),
    headers = list(list(
      id = "h", source_data = "adam.adsl", orientation = "landscape",
      columns = list(list(
        id = "all", label = "All", condition = "1", display_order = 1L,
        width = 1, alignment = "center"
      ))
    )),
    tables = list(list(id = "t", population_id = "p", header_id = "h",
                       template_id = "tpl")),
    templates = list(list(id = "tpl", body = list(chunks = list(chunk))))
  )
}

# parse_bundle_value reports failures through `value = NULL` plus an error list,
# so validity is "no collected errors" rather than a boolean flag.
bundle_passed <- function(parsed) {
  !is.null(parsed$value) && length(parsed$errors) == 0L
}

error_codes <- function(bundle) {
  result <- parse_bundle_value(bundle)
  if (bundle_passed(result)) return(character())
  vapply(result$errors, `[[`, "", "code")
}

# Drop a named field from a list without touching the others.
without_field <- function(value, field) {
  value[[field]] <- NULL
  value
}

testthat::test_that("primitive chunk types require a counting unit", {
  registry <- default_chunk_registry()
  for (type in c("continuous_summary", "categorical_summary_nonexclusive",
                 "categorical_summary_exclusive")) {
    definition <- chunk_registry_lookup(registry, type)
    testthat::expect_true("counting_unit" %in% definition$required_fields)
    testthat::expect_true("distinct_key" %in% definition$optional_fields)
    testthat::expect_identical(definition$field_types$counting_unit, "string")
    testthat::expect_identical(definition$field_types$distinct_key, "sequence")
  }
})

testthat::test_that("a missing counting unit is a required-field failure", {
  codes <- error_codes(counting_unit_bundle(without_field(counting_unit_chunk(), "counting_unit")))
  testthat::expect_true("bundle_required_field_missing" %in% codes)
})

testthat::test_that("an unsupported counting unit is a value failure", {
  codes <- error_codes(counting_unit_bundle(counting_unit_chunk(list(counting_unit = "unit"))))
  testthat::expect_true("bundle_value_invalid" %in% codes)
})

testthat::test_that("distinct_key requires the distinct_key counting unit", {
  missing <- counting_unit_chunk(list(counting_unit = "distinct_key"))
  codes <- error_codes(counting_unit_bundle(missing))
  testthat::expect_true("bundle_required_field_missing" %in% codes)

  unexpected <- counting_unit_chunk(list(distinct_key = list("USUBJID")))
  codes <- error_codes(counting_unit_bundle(unexpected))
  testthat::expect_true("bundle_value_invalid" %in% codes)
})

testthat::test_that("distinct_key is kept only for the distinct_key unit", {
  chunk <- counting_unit_chunk(list(
    counting_unit = "distinct_key", distinct_key = list("USUBJID", "AESEQ")
  ))
  result <- parse_bundle_value(counting_unit_bundle(chunk))
  testthat::expect_true(bundle_passed(result))
  parsed <- result$value$templates[[1L]]$body$chunks[[1L]]
  testthat::expect_identical(parsed$counting_unit, "distinct_key")
  testthat::expect_identical(parsed$distinct_key, c("USUBJID", "AESEQ"))

  plain <- parse_bundle_value(counting_unit_bundle(counting_unit_chunk()))
  testthat::expect_true(bundle_passed(plain))
  testthat::expect_null(plain$value$templates[[1L]]$body$chunks[[1L]]$distinct_key)
})

testthat::test_that("repeated distinct key fields are rejected", {
  chunk <- counting_unit_chunk(list(
    counting_unit = "distinct_key", distinct_key = list("USUBJID", "USUBJID")
  ))
  codes <- error_codes(counting_unit_bundle(chunk))
  testthat::expect_true("bundle_value_invalid" %in% codes)
})

testthat::test_that("counting unit and distinct key survive a YAML round trip", {
  cases <- list(
    list(counting_unit = "record"),
    list(counting_unit = "distinct_subject"),
    list(counting_unit = "distinct_key", distinct_key = list("USUBJID", "AESEQ"))
  )
  for (case in cases) {
    chunk <- counting_unit_chunk(case)
    bundle <- counting_unit_bundle(chunk)
    text <- canonical_yaml_text(bundle)
    testthat::expect_match(text, paste0("counting_unit: '", case$counting_unit, "'"), fixed = TRUE)
    restored <- parse_bundle_yaml(text)
    testthat::expect_true(restored$passed)
    parsed <- restored$workspace$templates[[1L]]$body$chunks[[1L]]
    testthat::expect_identical(parsed$counting_unit, case$counting_unit)
    if (identical(case$counting_unit, "distinct_key")) {
      testthat::expect_identical(parsed$distinct_key, c("USUBJID", "AESEQ"))
    } else {
      testthat::expect_null(parsed$distinct_key)
    }
  }
})

testthat::test_that("hierarchical blocks keep their own counting unit contract", {
  # A hierarchical chunk declares counting_unit per analysis block; the chunk
  # itself must not accept a chunk-level counting_unit.
  row <- list(id = "r1", type = "analysis", label = "Subjects", condition = "1",
              statistics = list(list(id = "n")), cell_format = "{n}")
  block <- list(
    id = "a1", anchor_level = "l1", placement = "below",
    type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
    denominator = list(scope = "header_population", unit = "distinct_subject"),
    rows = list(row)
  )
  chunk <- list(
    id = "ch", type = "hierarchical_summary", source_data = "adam.adae",
    source_contract = list(grain = "record", subject_key = "USUBJID",
                           record_key = c("USUBJID", "AESEQ"),
                           duplicate_policy = "error"),
    levels = list(list(
      id = "l1", variable = "SOC", order_variable = "SOC", order_direction = "asc",
      node_role = "label", missing_policy = "exclude"
    )),
    analysis_blocks = list(block)
  )
  result <- parse_bundle_value(counting_unit_bundle(chunk))
  testthat::expect_true(bundle_passed(result))
  parsed <- result$value$templates[[1L]]$body$chunks[[1L]]
  testthat::expect_null(parsed$counting_unit)
  testthat::expect_identical(parsed$analysis_blocks[[1L]]$counting_unit, "distinct_subject")
})