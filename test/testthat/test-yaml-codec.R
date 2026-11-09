valid_bundle_yaml <- function() {
  paste(
    "schema_version: 2",
    "populations:",
    "  - id: safety",
    "    label: Safety population",
    "    expression: 'SAFFL = \"Y\"'",
    "headers:",
    "  - id: treatment",
    "    source_data: '&ADSL'",
    "    orientation: landscape",
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
    "          counting_unit: distinct_subject",
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
  testthat::expect_match(text, "schema_version: 2\\n")
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

testthat::test_that("archive boundary rejects missing and unknown entries", {
  bytes <- canonical_archive_bytes(new_metadata_bundle())$bytes
  tmp <- tempfile(fileext = ".zip")
  writeBin(bytes, tmp)
  # The canonical archive always contains the minimal required entries.
  testthat::expect_true(length(bytes) > 0L)
  unknown <- parse_bundle_archive(charToRaw("not a zip"))
  testthat::expect_false(unknown$passed)
})

testthat::test_that("strict structure reports unknown fields and type discriminators", {
  input <- gsub(
    "schema_version: 2",
    "schema_version: 2\nextra: true",
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
      id = "h", source_data = "ADAM.ADSL", orientation = "landscape",
      page_rows = default_page_rows,
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
        levels = list(level), analysis_blocks = list(block)
      )))
    ))
  )
  encoded <- canonical_yaml_text(bundle)
  decoded <- parse_bundle_yaml(encoded)
  testthat::expect_true(decoded$passed)
  testthat::expect_identical(decoded$workspace, bundle)
  testthat::expect_match(encoded, "result_sort:\\n")
})

testthat::test_that("format levels round-trip without order fields", {
  bundle <- new_metadata_bundle(
    templates = list(list(
      id = "format_template",
      body = list(chunks = list(list(
        id = "format_hierarchy", type = "hierarchical_summary", source_data = "ADAE",
        levels = list(list(
          id = "visit", variable = "AVISITN", format = "visit_fmt",
          node_role = "label", missing_policy = "exclude"
        )),
        analysis_blocks = list(list(
          id = "counts", anchor_level = "visit", placement = "below",
          type = "categorical_summary_nonexclusive", counting_unit = "record",
          denominator = list(scope = "header_population", unit = "distinct_subject"),
          rows = list(list(
            id = "n", type = "analysis", label = "N", condition = "1",
            statistics = list(list(id = "n")), cell_format = "{n}"
          ))
        ))
      )))
    ))
  )
  encoded <- canonical_yaml_text(bundle)
  decoded <- parse_bundle_yaml(encoded)
  testthat::expect_true(decoded$passed)
  testthat::expect_identical(decoded$workspace, bundle)
  testthat::expect_match(encoded, "format: 'visit_fmt'", fixed = TRUE)
  testthat::expect_false(grepl("order_variable:", encoded, fixed = TRUE))
})

testthat::test_that("feature scanner ignores controls in quoted and literal text", {
  text <- paste(
    "schema_version: 2",
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

testthat::test_that("ZIP metadata archive round-trips with independent object files", {
  bundle <- parse_bundle_yaml(valid_bundle_yaml())$workspace
  archive <- canonical_archive_bytes(bundle)
  testthat::expect_s3_class(archive, "CanonicalArchiveBytes")
  decoded <- parse_bundle_archive(archive)
  testthat::expect_true(decoded$passed)
  testthat::expect_identical(
    vapply(decoded$workspace$templates, `[[`, "", "id"),
    "demog"
  )
  testthat::expect_identical(
    vapply(decoded$workspace$tables, `[[`, "", "id"),
    "t1"
  )

  zip_path <- tempfile(fileext = ".zip")
  on.exit(unlink(zip_path, force = TRUE), add = TRUE)
  writeBin(archive$bytes, zip_path)
  entries <- zip::zip_list(zip_path)$filename
  testthat::expect_identical(
    entries,
    c("manifest.yaml", "populations.yaml", "headers.yaml",
      "tables/t1.yaml", "templates/demog.yaml")
  )
  second <- canonical_archive_bytes(decoded$workspace)
  testthat::expect_identical(archive$bytes, second$bytes)
})

testthat::test_that("ZIP metadata archive requires manifest and catalogs", {
  staging <- tempfile("tfl_missing_archive_")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  writeLines("schema_version: 2", file.path(staging, "manifest.yaml"), useBytes = TRUE)
  zip_path <- tempfile(fileext = ".zip")
  on.exit(unlink(zip_path, force = TRUE), add = TRUE)
  zip::zipr(zip_path, files = "manifest.yaml", recurse = FALSE,
            include_directories = FALSE, root = staging, mode = "cherry-pick")
  bytes <- readBin(zip_path, "raw", n = file.info(zip_path)$size)
  result <- parse_bundle_archive(bytes)
  testthat::expect_false(result$passed)
  testthat::expect_identical(result$errors[[1L]]$code, "bundle_entry_missing")
})

testthat::test_that("ZIP structure rejects unknown entries and filename identity mismatches", {
  bundle <- parse_bundle_yaml(valid_bundle_yaml())$workspace
  texts <- encode_archive_texts(bundle)
  staging <- tempfile("tfl_archive_structure_"); dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  for (name in names(texts)) {
    path <- file.path(staging, name); dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(texts[[name]], path, useBytes = TRUE)
  }
  writeLines("unexpected", file.path(staging, "notes.txt"), useBytes = TRUE)
  zip_path <- tempfile(fileext = ".zip"); on.exit(unlink(zip_path, force = TRUE), add = TRUE)
  zip::zipr(zip_path, files = c("manifest.yaml", "populations.yaml", "headers.yaml", "tables", "templates", "notes.txt"), root = staging, include_directories = FALSE)
  result <- parse_bundle_archive(readBin(zip_path, "raw", n = file.info(zip_path)$size))
  testthat::expect_false(result$passed)
  testthat::expect_identical(result$errors[[1L]]$code, "bundle_entry_invalid")

  writeLines(gsub("demog", "renamed", texts[["templates/demog.yaml"]], fixed = TRUE),
             file.path(staging, "templates", "demog.yaml"), useBytes = TRUE)
  zip_path2 <- tempfile(fileext = ".zip"); on.exit(unlink(zip_path2, force = TRUE), add = TRUE)
  zip::zipr(zip_path2, files = c("manifest.yaml", "populations.yaml", "headers.yaml", "tables", "templates"), root = staging, include_directories = FALSE)
  result2 <- parse_bundle_archive(readBin(zip_path2, "raw", n = file.info(zip_path2)$size))
  testthat::expect_false(result2$passed)
  testthat::expect_true(any(vapply(result2$errors, function(x) identical(x$code, "bundle_file_identity_invalid"), logical(1))))
})

# A level is format-driven or variable-driven, never both. A format supplies the
# node domain, the display label and the node order together, so label_variable
# and order_variable/order_direction each restate one of those from a source that
# cannot serve values the data does not contain. Accepting the combination used
# to discard what the caller wrote, with no diagnostic at all.
testthat::test_that("a level rejects label and order fields together with format", {
  build <- function(extra) {
    level <- paste(c(
      "        - id: l1",
      "          variable: SOC",
      "          node_role: analysis",
      "          node_analysis_id: a1",
      "          missing_policy: exclude",
      extra
    ), collapse = "\n")
    paste(c(
      "schema_version: 2",
      "populations:",
      "  - id: p",
      "    label: Population",
      "    expression: '1'",
      "headers: []",
      "tables:",
      "  - id: t",
      "    population_id: p",
      "    header_id: h",
      "    template_id: x",
      "templates:",
      "  - id: x",
      "    body:",
      "      chunks:",
      "      - id: ch",
      "        type: hierarchical_summary",
      "        source_data: work.events",
      "        analysis_blocks:",
      "        - id: a1",
      "          anchor_level: l1",
      "          placement: same_row",
      "          type: categorical_summary_nonexclusive",
      "          counting_unit: distinct_subject",
      "          denominator:",
      "            scope: header_population",
      "            unit: distinct_subject",
      "          rows:",
      "          - id: r1",
      "            type: analysis",
      "            label: Subjects",
      "            condition: '1'",
      "            statistics:",
      "            - id: 'n'",
      "            cell_format: '{n}'",
      "        levels:",
      level
    ), collapse = "\n")
  }
  # The unformatted level still needs an order variable and direction, so that is
  # the baseline that must parse.
  unformatted <- build(c("          order_variable: SOCN", "          order_direction: asc"))
  testthat::expect_true(parse_bundle_yaml(unformatted)$passed)

  # A formatted level needs neither, and is the other valid shape.
  formatted <- build("          format: $soc_fmt")
  testthat::expect_true(parse_bundle_yaml(formatted)$passed)

  for (field in c("label_variable", "order_variable", "order_direction")) {
    offending <- build(c("          format: $soc_fmt", paste0("          ", field, ": X")))
    result <- parse_bundle_yaml(offending)
    testthat::expect_false(result$passed, info = field)
    messages <- vapply(result$errors, `[[`, "", "message")
    testthat::expect_true(any(grepl(field, messages, fixed = TRUE)), info = field)
    testthat::expect_true(any(grepl("cannot be combined with 'format'", messages,
                                    fixed = TRUE)), info = field)
  }

  # A formatted level also no longer requires, and must not be forced into,
  # the order pair: the format drives ordering by itself.
  both <- build(c("          format: $soc_fmt", "          order_variable: SOCN",
                  "          order_direction: asc"))
  testthat::expect_false(parse_bundle_yaml(both)$passed)
})

testthat::test_that("page_rows parses, defaults, and round-trips canonically", {
  column <- list(id = "c1", label = "Overall", condition = "1", display_order = 1L,
                 width = 1, alignment = "center")
  build <- function(page_rows = NULL) {
    header <- list(id = "h", source_data = "ADAM.ADSL", orientation = "portrait",
                   columns = list(column))
    if (!is.null(page_rows)) header$page_rows <- page_rows
    new_metadata_bundle(headers = list(header))
  }

  default <- parse_bundle_yaml(canonical_yaml_text(build()))
  testthat::expect_true(default$passed)
  testthat::expect_identical(default$workspace$headers[[1L]]$page_rows, default_page_rows)

  explicit <- parse_bundle_yaml(canonical_yaml_text(build(18L)))
  testthat::expect_true(explicit$passed)
  testthat::expect_identical(explicit$workspace$headers[[1L]]$page_rows, 18L)

  # The capacity is always written, including when it equals the default, so a
  # bundle states its own layout instead of inheriting whatever default_page_rows
  # happens to be when it is read. Changing the constant must not silently change
  # what an existing file means.
  testthat::expect_true(grepl(sprintf("page_rows: %d", default_page_rows),
                              canonical_yaml_text(build()), fixed = TRUE))
  testthat::expect_true(grepl("page_rows: 18", canonical_yaml_text(build(18L)), fixed = TRUE))
  # And it survives two round trips unchanged, so the emitted value is stable.
  twice <- parse_bundle_yaml(canonical_yaml_text(
    parse_bundle_yaml(canonical_yaml_text(build()))$workspace))
  testthat::expect_true(grepl(sprintf("page_rows: %d", default_page_rows),
                              canonical_yaml_text(twice$workspace), fixed = TRUE))

  # Zero means "never break"; a negative capacity is not a page.
  zero <- parse_bundle_yaml(canonical_yaml_text(build(0L)))
  testthat::expect_true(zero$passed)
  testthat::expect_identical(zero$workspace$headers[[1L]]$page_rows, 0L)
  # A negative capacity is rejected at the model boundary; encoding refuses to
  # emit it at all, so assert that refusal rather than a round trip.
  testthat::expect_error(canonical_yaml_text(build(-1L)), "invalid metadata bundle")

  # Four lines is the smallest page that can be honoured. Two of them are the
  # page-edge blanks, leaving two for the body: a block separator plus one content
  # row. At 3 the body holds a single row, so every block after the first is
  # oversized, the separator ends up alone on a page, and a blank page is
  # printed. 1, 2 and 3 are refused rather than silently inflated.
  smallest <- parse_bundle_yaml(canonical_yaml_text(build(4L)))
  testthat::expect_true(smallest$passed)
  testthat::expect_identical(smallest$workspace$headers[[1L]]$page_rows, 4L)
  # A capacity of 4 leaves exactly two body rows, the minimum for a separator and
  # one content row.
  four <- parse_bundle_yaml(canonical_yaml_text(build(4L)))
  testthat::expect_identical(four$workspace$headers[[1L]]$page_rows - 2L, 2L)
  # Encoding refuses an invalid bundle outright, so the rejection is observed on
  # the parsed value rather than through a canonical round trip.
  for (too_small in c(1L, 2L, 3L)) {
    header <- list(id = "h", source_data = "ADAM.ADSL", orientation = "portrait",
                   page_rows = too_small, columns = list(column))
    errors <- parse_bundle_value(new_metadata_bundle(headers = list(header)))$errors
    testthat::expect_true(length(errors) > 0L, label = as.character(too_small))
    testthat::expect_true(any(grepl("page_rows", vapply(errors, `[[`, "", "path"))))
  }

  # There is an upper bound too. page_break_source() converts the parsed value with
  # as.integer(), so a capacity outside the integer range would silently become NA
  # and every pagination guard would read `> NA`. parse_integer_value() returns a
  # double above that range on purpose, for fields that genuinely need big
  # integers; a page capacity is not one of them.
  largest <- parse_bundle_yaml(canonical_yaml_text(build(.Machine$integer.max)))
  testthat::expect_true(largest$passed)
  testthat::expect_identical(as.numeric(largest$workspace$headers[[1L]]$page_rows),
                             as.numeric(.Machine$integer.max))
  for (too_large in c(2147483648, 1e10)) {
    header <- list(id = "h", source_data = "ADAM.ADSL", orientation = "portrait",
                   page_rows = too_large, columns = list(column))
    errors <- parse_bundle_value(new_metadata_bundle(headers = list(header)))$errors
    testthat::expect_true(length(errors) > 0L, label = as.character(too_large))
    testthat::expect_true(any(grepl("page_rows", vapply(errors, `[[`, "", "path"))))
  }
})

testthat::test_that("an out-of-range integer is rejected, not coerced to NA", {
  # Same defect class as page_rows: parse_integer_value() returns a double above
  # the integer range on purpose, so a later as.integer() turns it into NA and the
  # error reports a consequence instead of the value that was typed. Each of these
  # used to emit "NAs introduced by coercion to integer range" and then complain
  # about something else entirely.
  make <- function(ord) {
    list(id = "h", source_data = "ADAM.ADSL", orientation = "portrait",
         page_rows = 22L,
         columns = list(list(id = "c1", label = "O", condition = "1",
                             display_order = ord, width = 1, alignment = "center")))
  }
  for (too_large in c(2147483648, 1e10)) {
    warnings <- character()
    value <- withCallingHandlers(
      parse_bundle_value(new_metadata_bundle(headers = list(make(too_large)))),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      })
    # No coercion warning: the value is refused where it is parsed.
    testthat::expect_identical(warnings, character(), label = as.character(too_large))
    testthat::expect_true(length(value$errors) > 0L, label = as.character(too_large))
    testthat::expect_true(
      any(grepl("display_order", vapply(value$errors, `[[`, "", "path"))),
      label = as.character(too_large))
  }
})

testthat::test_that("a huge relative digits offset fails with a message, not an R error", {
  # The relative form is parsed out of text, so its magnitude is unbounded even
  # though a digits count is not. Converting it directly with as.integer() warned
  # and produced NA, and the following comparison then died with
  # "missing value where TRUE/FALSE needed".
  for (offset in c("+99999999999", "-99999999999")) {
    message <- tryCatch({
      suppressWarnings(resolve_relative_digits(22L, offset))
      NA_character_
    }, error = function(e) conditionMessage(e))
    testthat::expect_false(is.na(message), label = offset)
    testthat::expect_false(
      grepl("missing value where TRUE/FALSE needed", message, fixed = TRUE),
      label = offset)
    testthat::expect_true(grepl("digits", message, ignore.case = TRUE), label = offset)
  }
  # Ordinary offsets still resolve, so the bound is not blanket rejection.
  testthat::expect_identical(resolve_relative_digits(22L, "+2"), 24L)
  testthat::expect_identical(resolve_relative_digits(22L, "-1"), 21L)
})

testthat::test_that("indent_level refuses values the emitter cannot emit", {
  # indent_level is emitted with as.integer(), so an out-of-range value becomes NA
  # and the generated SAS literally contains `indent_level = NA`, which is not a
  # valid row attribute. The model has to refuse it where it is written.
  # A "label" row is the simplest valid type for continuous_summary (no statistics,
  # no cell_format) and indent_level is a common field, which is all this needs.
  row <- function(level) {
    list(id = "r1", type = "label", label = "L", indent_level = level)
  }
  # Use the registered continuous contract so the row type is valid; only
  # indent_level is under test here.
  definition <- default_chunk_registry()$definitions[["continuous_summary"]]
  parse_row <- function(level) {
    captured <- new_error_collector()
    parse_row_value(row(level), "$.row", captured, definition)
    error_items(captured)
  }
  for (too_large in c(2147483648, 1e10)) {
    errors <- parse_row(too_large)
    testthat::expect_true(length(errors) > 0L, label = as.character(too_large))
    testthat::expect_true(
      any(grepl("indent_level", vapply(errors, `[[`, "", "path"))),
      label = as.character(too_large))
  }
  # A representable level still parses, so the bound is not blanket rejection.
  testthat::expect_identical(parse_row(2L), list())
})

testthat::test_that("an unresolvable digits value fails clearly, not inside the emitter", {
  # Third instance of the same class as page_rows. digits is parsed with
  # parse_integer_value(), which returns a double above the integer range, and the
  # precision resolver then compares with as.integer(digits). For 1e10 that is NA,
  # the comparison yields NA, and the emitter dies with the R-level message
  # "missing value where TRUE/FALSE needed" -- naming no field and no value.
  for (bad in c(1e10, 2147483648)) {
    message <- tryCatch({
      suppressWarnings(resolve_relative_digits(22L, bad))
      NA_character_
    }, error = function(e) conditionMessage(e))
    testthat::expect_false(is.na(message), label = format(bad))
    testthat::expect_false(
      grepl("missing value where TRUE/FALSE needed", message, fixed = TRUE),
      label = paste("opaque failure for", format(bad)))
    testthat::expect_true(
      grepl("digits", message, ignore.case = TRUE),
      label = paste("message should name the field for", format(bad)))
  }
})
