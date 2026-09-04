valid_bundle_yaml <- function() {
  paste(
    "schema_version: 1",
    "populations:",
    "  - id: safety",
    "    label: Safety population",
    "    expression: 'SAFFL = \"Y\"'",
    "headers:",
    "  - id: treatment",
    "    source_data: '&ADSL'",
    "    columns:",
    "      - id: overall",
    "        label: Overall",
    "        condition: '1'",
    "        display_order: 1",
    "        width: 1.2",
    "        alignment: center",
    "tables:",
    "  - id: t1",
    "    population_id: safety",
    "    header_id: treatment",
    "    template_id: demog",
    "    custom_code:",
    "      before: |",
    "        %let source=ADSL;",
    "templates:",
    "  - id: demog",
    "    body:",
    "      stub_header: Characteristic",
    "      chunks:",
    "        - id: c1",
    "          type: continuous_summary",
    "          source_data: adam.adsl",
    "          analysis_variable: AGE",
    "          rows:",
    "            - id: r1",
    "              type: analysis",
    "              label: Mean (SD)",
    "              statistics:",
    "                - id: mean",
    "                  digits: 1",
    "                - id: sd",
    "                  digits: '+1'",
    "              cell_format: '{mean} ({sd})'",
    sep = "\n"
  )
}

testthat::test_that("valid YAML decodes and canonical round-trips", {
  result <- parse_bundle_yaml(valid_bundle_yaml())
  testthat::expect_true(result$passed)
  testthat::expect_type(result$workspace, "list")
  bytes <- canonical_yaml_bytes(result$workspace)
  testthat::expect_s3_class(bytes, "CanonicalBytes")
  text <- as.character(bytes)
  testthat::expect_match(text, "schema_version: 1\\n")
  testthat::expect_match(text, "source_data: '&ADSL'")
  testthat::expect_true(grepl("before: |", text, fixed = TRUE))
  testthat::expect_false(grepl("\\r", text))
  second <- parse_bundle_yaml(bytes)
  testthat::expect_true(second$passed)
  testthat::expect_identical(result$workspace, second$workspace)
  testthat::expect_identical(text, as.character(canonical_yaml_bytes(second$workspace)))
})

testthat::test_that("transport and unsupported YAML features have stable root errors", {
  missing <- parse_bundle_yaml(raw())
  testthat::expect_identical(missing$errors[[1]]$code, "bundle_input_missing")
  duplicate <- parse_bundle_yaml("a: 1\na: 2")
  testthat::expect_identical(duplicate$errors[[1]]$code, "bundle_duplicate_key")
  anchor <- parse_bundle_yaml("a: &x 1")
  testthat::expect_identical(anchor$errors[[1]]$code, "bundle_yaml_invalid")
  multi <- parse_bundle_yaml("---\na: 1\n---\nb: 2")
  testthat::expect_identical(multi$errors[[1]]$code, "bundle_yaml_invalid")
  invalid_utf8 <- parse_bundle_yaml(as.raw(c(0xff, 0xfe)))
  testthat::expect_identical(invalid_utf8$errors[[1]]$code, "bundle_encoding_invalid")
  bom_crlf <- parse_bundle_yaml(charToRaw(paste0("\ufeff", gsub("\n", "\r\n", valid_bundle_yaml(), fixed = TRUE))))
  testthat::expect_true(bom_crlf$passed)
  testthat::expect_false(grepl("\\r", as.character(canonical_yaml_bytes(bom_crlf$workspace))))
  tag <- parse_bundle_yaml("a: !!str 1")
  testthat::expect_identical(tag$errors[[1]]$code, "bundle_yaml_invalid")
  merge_key <- parse_bundle_yaml("a: 1\nb:\n  <<: {c: 2}")
  testthat::expect_identical(merge_key$errors[[1]]$code, "bundle_yaml_invalid")
})

testthat::test_that("strict structure reports unknown fields and type discriminators", {
  input <- gsub(
    "schema_version: 1",
    "schema_version: 1\nextra: true",
    valid_bundle_yaml(), fixed = TRUE
  )
  result <- parse_bundle_yaml(input)
  testthat::expect_false(result$passed)
  testthat::expect_true(any(vapply(result$errors, function(item)
    identical(item$code, "bundle_unknown_field"), logical(1L))))
  unknown_type <- gsub("continuous_summary", "unknown_summary", valid_bundle_yaml(), fixed = TRUE)
  result <- parse_bundle_yaml(unknown_type)
  testthat::expect_false(result$passed)
  testthat::expect_true(any(vapply(result$errors, function(item)
    identical(item$code, "bundle_chunk_type_unknown"), logical(1L))))
  missing_field <- gsub("    header_id: treatment\n", "", valid_bundle_yaml(), fixed = TRUE)
  result <- parse_bundle_yaml(missing_field)
  testthat::expect_true(any(vapply(result$errors, function(item)
    identical(item$code, "bundle_required_field_missing"), logical(1L))))
  duplicate_lines <- strsplit(valid_bundle_yaml(), "\n", fixed = TRUE)[[1L]]
  headers_position <- match("headers:", duplicate_lines)
  duplicate_id <- paste(
    c(duplicate_lines[seq_len(headers_position - 1L)],
      "  - id: safety",
      "    label: Safety duplicate",
      "    expression: '1'",
      duplicate_lines[headers_position:length(duplicate_lines)]),
    collapse = "\n"
  )
  result <- parse_bundle_yaml(duplicate_id)
  testthat::expect_true(any(vapply(result$errors, function(item)
    item$code %in% c("bundle_id_invalid", "bundle_yaml_invalid"), logical(1L))))
  invalid_width <- gsub("width: 1.2", "width: 0", valid_bundle_yaml(), fixed = TRUE)
  result <- parse_bundle_yaml(invalid_width)
  testthat::expect_true(any(vapply(result$errors, function(item)
    identical(item$code, "bundle_value_invalid"), logical(1L))))
})

testthat::test_that("relative digits, placeholder mismatch, and delayed references are handled", {
  input <- valid_bundle_yaml()
  input <- gsub("template_id: demog", "template_id: not_loaded", input, fixed = TRUE)
  result <- parse_bundle_yaml(input)
  testthat::expect_true(result$passed)
  bad_format <- gsub("'{mean} ({sd})'", "'{mean}'", input, fixed = TRUE)
  result <- parse_bundle_yaml(bad_format)
  testthat::expect_false(result$passed)
  testthat::expect_true(any(vapply(result$errors, function(item)
    grepl("placeholders", item$message, fixed = TRUE), logical(1L))))
})

testthat::test_that("canonical numeric formatting avoids scientific notation", {
  testthat::expect_identical(canonical_decimal(1e20), "100000000000000000000")
  testthat::expect_identical(canonical_decimal(1e-8), "0.00000001")
  testthat::expect_identical(canonical_decimal(-0), "0")
  testthat::expect_identical(canonical_decimal(1.2300), "1.23")
  testthat::expect_identical(canonical_decimal(-1.2e-20),
                             "-0.000000000000000000012")
  testthat::expect_identical(canonical_decimal(9.99999999999999e307),
                             paste0("999999999999999", strrep("0", 293L)))
})

testthat::test_that("hierarchical source and result-sort fields round-trip", {
  row <- list(
    id = "r1", type = "analysis", label = "Subjects", condition = "1",
    statistics = list(list(id = "n")), cell_format = "{n}"
  )
  block <- list(
    id = "a1", anchor_level = "l1", placement = "below",
    type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
    denominator = list(scope = "header_population", unit = "distinct_subject"),
    rows = list(row)
  )
  level <- list(
    id = "l1", variable = "SOC", order_variable = "SOCN", order_direction = "asc",
    result_sort = list(
      metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "n"),
      column_order = c(1L, 0L), direction = "desc"
    ),
    node_role = "label", missing_policy = "exclude"
  )
  bundle <- new_metadata_bundle(
    headers = list(list(
      id = "h", source_data = "ADAM.ADSL",
      columns = list(list(
        id = "c1", label = "Overall", condition = "1", display_order = 1L,
        width = 1, alignment = "center"
      ))
    )),
    tables = list(list(
      id = "t", population_id = "missing", header_id = "h", template_id = "x"
    )),
    templates = list(list(
      id = "x", body = list(chunks = list(list(
        id = "ch", type = "hierarchical_summary", source_data = "ADAE",
        source_contract = list(
          grain = "record", subject_key = "USUBJID",
          record_key = c("USUBJID", "AESEQ"), duplicate_policy = "error"
        ),
        levels = list(level), analysis_blocks = list(block)
      )))
    ))
  )
  encoded <- canonical_yaml_text(bundle)
  decoded <- parse_bundle_yaml(encoded)
  testthat::expect_true(decoded$passed)
  testthat::expect_identical(decoded$workspace, bundle)
  testthat::expect_match(encoded, "record_key:\\n")
  testthat::expect_match(encoded, "result_sort:\\n")
})

testthat::test_that("feature scanner ignores controls in quoted and literal text", {
  text <- paste(
    "schema_version: 1",
    "populations:",
    "  - id: p",
    "    label: \"contains &anchor and !tag\"",
    "    expression: '1 # not a comment'",
    "headers: []",
    "tables:",
    "  - id: t",
    "    population_id: p",
    "    header_id: h",
    "    template_id: x",
    "    custom_code:",
    "      before: |",
    "        %let x=&value; # source text",
    "templates: []",
    sep = "\n"
  )
  result <- parse_bundle_yaml(text)
  testthat::expect_true(result$passed)
  testthat::expect_false(any(vapply(result$errors, function(item) {
    item$code == "bundle_yaml_invalid" && grepl("anchor|tag", item$message)
  }, logical(1L))))
})
