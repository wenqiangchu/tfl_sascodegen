# Guards the dummy study metadata bundle.
#
# The bundle under dummy_study/metadata/ is authored as plain YAML and must stay
# loadable by the production codec and model. dummy_study/tools/check_metadata.R
# performs the full check (archive round trip plus deterministic source
# generation for all six tables, about eight seconds); this file keeps the
# schema contract inside the normal R suite by parsing and validating the bundle
# and generating one table end to end.

metadata_dir <- file.path(project_root, "dummy_study", "metadata")

read_bundle_entry <- function(relative_path) {
  text <- paste(readLines(file.path(metadata_dir, relative_path), warn = FALSE,
                          encoding = "UTF-8"), collapse = "\n")
  parsed <- parse_yaml_document_text(text)
  testthat::expect_length(parsed$errors, 0L)
  parsed$value
}

load_dummy_bundle <- function() {
  tables <- sort(list.files(file.path(metadata_dir, "tables"), pattern = "\\.yaml$",
                            full.names = TRUE))
  templates <- sort(list.files(file.path(metadata_dir, "templates"), pattern = "\\.yaml$",
                               full.names = TRUE))
  read_all <- function(paths) {
    lapply(paths, function(path) {
      parsed <- parse_yaml_document_text(
        paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
      testthat::expect_length(parsed$errors, 0L)
      parsed$value
    })
  }
  new_metadata_bundle(
    populations = read_bundle_entry("populations.yaml")$populations,
    headers = read_bundle_entry("headers.yaml")$headers,
    tables = unname(read_all(tables)),
    templates = unname(read_all(templates))
  )
}

testthat::test_that("the dummy study bundle parses without model errors", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  manifest <- read_bundle_entry("manifest.yaml")
  testthat::expect_identical(as.integer(manifest$schema_version), 2L)

  parsed <- parse_bundle_value(load_dummy_bundle())
  messages <- vapply(parsed$errors, function(error) error$message, character(1L))
  testthat::expect_length(parsed$errors, 0L)
  if (length(parsed$errors) > 0L) {
    # Surface the paths so a failure names the offending field.
    message(paste(messages, collapse = "\n"))
  }
})

testthat::test_that("the dummy study bundle keeps the planned object set", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  testthat::expect_identical(sort(vapply(workspace$populations, `[[`, "", "id")),
                             sort(c("efficacy", "itt", "randomized", "safety")))
  testthat::expect_identical(sort(vapply(workspace$headers, `[[`, "", "id")),
                             sort(c("shift_header", "trt01a_header", "trt01p_header")))
  testthat::expect_identical(sort(vapply(workspace$tables, `[[`, "", "id")), sort(c(
    "t_14_1_1_disposition", "t_14_1_2_baseline", "t_14_2_3_hgb_shift",
    "t_14_3_1_2_teae", "t_14_3_1_4_teae_severity", "t_14_3_2_1_hgb_by_visit")))
  testthat::expect_identical(length(workspace$templates), 6L)
})

testthat::test_that("every dummy study table resolves its references", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  population_ids <- vapply(workspace$populations, `[[`, "", "id")
  header_ids <- vapply(workspace$headers, `[[`, "", "id")
  template_ids <- vapply(workspace$templates, `[[`, "", "id")
  for (table in workspace$tables) {
    testthat::expect_true(table$population_id %in% population_ids,
                          label = paste(table$id, "population"))
    testthat::expect_true(table$header_id %in% header_ids,
                          label = paste(table$id, "header"))
    testthat::expect_true(table$template_id %in% template_ids,
                          label = paste(table$id, "template"))
  }
})

testthat::test_that("the disposition table generates deterministically", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  first <- generate_table_source(workspace, "t_14_1_1_disposition", output_mode = "report")
  testthat::expect_true(first$passed)
  second <- generate_table_source(workspace, "t_14_1_1_disposition", output_mode = "report")
  testthat::expect_identical(first$source, second$source)
  source_text <- paste(first$source, collapse = "\n")
  testthat::expect_match(source_text, "discontinued", fixed = TRUE)
  testthat::expect_match(source_text, "Withdrew Consent", fixed = TRUE)
})

# The four assertions below pin the fixes P4 needed after the first real SAS run.
# Each one failed before its fix, so a revert is caught here rather than by
# reading a generated program.

testthat::test_that("the visit level orders by AVISITN and declares no format", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  template <- workspace$templates[[match("tpl_hgb_by_visit",
                                        vapply(workspace$templates, `[[`, "", "id"))]]
  chunk <- template$body$chunks[[1L]]
  visit <- chunk$levels[[match("visit", vapply(chunk$levels, `[[`, "", "id"))]]
  # A declared format makes the emitter ignore order_variable and fall back to
  # the format catalog order, which sorts visits alphabetically.
  testthat::expect_null(visit$format)
  testthat::expect_identical(visit$order_variable, "AVISITN")
  testthat::expect_identical(visit$order_direction, "asc")
})

testthat::test_that("severity is a below row block, not a hierarchy level", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  template <- workspace$templates[[match("tpl_teae_severity",
                                        vapply(workspace$templates, `[[`, "", "id"))]]
  chunk <- template$body$chunks[[1L]]
  level_ids <- vapply(chunk$levels, `[[`, "", "id")
  # Severity is no longer a level: the report nests severity under both SOC and
  # PT, which two same_row levels cannot express. It is a below block instead.
  testthat::expect_identical(level_ids, c("soc", "pt"))
  for (level in chunk$levels) testthat::expect_null(level$format)

  blocks <- chunk$analysis_blocks
  block_ids <- vapply(blocks, `[[`, "", "id")
  placements <- vapply(blocks, `[[`, "", "placement")
  names(placements) <- block_ids
  testthat::expect_identical(placements[["soc_subjects"]], "same_row")
  testthat::expect_identical(placements[["pt_subjects"]], "same_row")
  testthat::expect_identical(placements[["soc_severity"]], "below")
  testthat::expect_identical(placements[["pt_severity"]], "below")

  # SOC-level severity must read the SOC-wide reduction. Conditioning it on the
  # per-SOC/PT SEV_ORDER counts a subject once per matching PT, so the three rows
  # overlap and sum to more than the SOC total.
  soc_severity <- blocks[[match("soc_severity", block_ids)]]
  conditions <- vapply(soc_severity$rows, `[[`, "", "condition")
  testthat::expect_true(all(grepl("SOC_SEV_ORDER", conditions, fixed = TRUE)))
  pt_severity <- blocks[[match("pt_severity", block_ids)]]
  pt_conditions <- vapply(pt_severity$rows, `[[`, "", "condition")
  testthat::expect_true(all(grepl("SEV_ORDER", pt_conditions, fixed = TRUE)))

  table <- workspace$tables[[match("t_14_3_1_4_teae_severity",
                                  vapply(workspace$tables, `[[`, "", "id"))]]
  before <- table$custom_code$before
  testthat::expect_match(before, "when 'SEVERE'   then 1", fixed = TRUE)
  testthat::expect_match(before, "min(case AESEV", fixed = TRUE)
  testthat::expect_match(before, "as SOC_SEV_ORDER", fixed = TRUE)
  # A self-referencing CREATE TABLE draws "recursive reference to the target
  # table", which the runner treats as an unclassified failure.
  testthat::expect_match(before, "WORK.AE_PTSEV", fixed = TRUE)
})

testthat::test_that("a WORK header source carries the population variables", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  header <- workspace$headers[[match("shift_header",
                                    vapply(workspace$headers, `[[`, "", "id"))]]
  testthat::expect_identical(header$source_data, "WORK.SHIFT_HGB")

  population <- workspace$populations[[match("safety",
                                            vapply(workspace$populations, `[[`, "", "id"))]]
  # The population expression is evaluated on the header source, so every
  # variable it names must exist in the derived dataset.
  testthat::expect_match(population$expression, "SAFFL", fixed = TRUE)

  table <- workspace$tables[[match("t_14_2_3_hgb_shift",
                                  vapply(workspace$tables, `[[`, "", "id"))]]
  testthat::expect_match(table$custom_code$before, "b.SAFFL", fixed = TRUE)
})

testthat::test_that("no dummy study template uses a visit format any more", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  formats <- unlist(lapply(workspace$templates, function(template) {
    unlist(lapply(template$body$chunks, function(chunk) {
      if (is.null(chunk$levels)) character() else
        vapply(chunk$levels, function(level) level$format %||% "", character(1L))
    }))
  }))
  testthat::expect_false("$TFLVISIT" %in% formats)
})

# The verification pair is only meaningful if it is runnable, and the embedded
# expectations in the shells are only meaningful if they are recomputed. This
# asserts the scripts exist, parse, and carry the contract that keeps the
# comparison honest rather than testing SAS output (which needs SAS installed).
testthat::test_that("the verification scripts are present and self-describing", {
  verify_dir <- file.path(project_root, "dummy_study", "verify")
  for (name in c("compute_expected.R", "compare_with_sas.R")) {
    path <- file.path(verify_dir, name)
    testthat::expect_true(file.exists(path), label = name)
    testthat::expect_no_error(parse(path))
  }

  expected_script <- paste(readLines(file.path(verify_dir, "compute_expected.R"),
                                     warn = FALSE), collapse = "\n")
  # Quantiles are computed but never asserted: PROC MEANS uses PCTLDEF = 5 while
  # R has nine quantile types, so agreement is reportable, not gating.
  testthat::expect_match(expected_script, "asserted_stats <- c(\"n\", \"mean\", \"sd\", \"min\", \"max\")",
                         fixed = TRUE)

  compare_script <- paste(readLines(file.path(verify_dir, "compare_with_sas.R"),
                                    warn = FALSE), collapse = "\n")
  # The cell comparison must round to the displayed precision, and follow the SAS
  # rule for halves, otherwise a correct value fails on a formatting difference.
  testthat::expect_match(compare_script, "sas_round", fixed = TRUE)
  testthat::expect_match(compare_script, "digits", fixed = TRUE)
  # A broken page break still yields the right numbers, so pagination needs its
  # own assertion against the paginated rows.
  testthat::expect_match(compare_script, "check_pagination", fixed = TRUE)
  testthat::expect_match(compare_script, "missing_last_blank", fixed = TRUE)
})

# The blank-line rule is a layout contract with no numeric signal, so the only
# way a regression can be caught is to assert the rule itself. It used to fire on
# every depth change, which put a blank row between a System Organ Class and its
# own Preferred Terms -- cutting apart a parent and its children.
testthat::test_that("blank rows mark block boundaries, not depth changes", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  result <- generate_table_source(workspace, "t_14_3_1_2_teae", output_mode = "report")
  testthat::expect_true(result$passed)
  source <- paste(result$source, collapse = "
")

  testthat::expect_match(source, "(hierarchy_level = 1 and row_role ne 'static') or",
                         fixed = TRUE)
  testthat::expect_match(source, "(previous_role = 'static' and row_role = 'dynamic')",
                         fixed = TRUE)
  # The retired condition must be gone: it is what split the SOC/PT nesting.
  testthat::expect_false(grepl("previous_level", source, fixed = TRUE))
})

# Pagination is a layout contract, so it is asserted on the emitted source and on
# the rows the program actually writes. The capacity counts printed lines,
# including the mandatory blank line at each page edge, because a blank row still
# occupies a line on the page.
testthat::test_that("pages respect page_rows, keep blocks whole, and pad both edges", {
  skip_if_not(file.exists(file.path(metadata_dir, "manifest.yaml")))
  workspace <- parse_bundle_value(load_dummy_bundle())$value
  header <- workspace$headers[[1L]]
  testthat::expect_identical(as.integer(header$page_rows), 22L)

  # A page is 22 printed lines: 20 for the body and 2 for the edge blanks.
  result <- generate_table_source(workspace, "t_14_3_1_4_teae_severity",
                                  output_mode = "report")
  testthat::expect_true(result$passed)
  source <- paste(result$source, collapse = "\n")
  testthat::expect_match(source, "2 are the page-edge blanks", fixed = TRUE)
  testthat::expect_match(source, "_rows_on_page + _block_rows > 20", fixed = TRUE)
  testthat::expect_match(source, "break after page_group / page", fixed = TRUE)
  # The footer must stay right aligned, roman and body-sized: footnote style=[...]
  # renders as literal text, so the overrides have to be inline and j=r is what
  # actually right-aligns the block.
  testthat::expect_match(source, "footnote1 j=r", fixed = TRUE)
  testthat::expect_match(source, "^S={fontstyle=roman fontweight=light fontsize=10pt}",
                         fixed = TRUE)
  testthat::expect_match(source, "Page ^{thispage} of ^{lastpage}", fixed = TRUE)
  # A block separator already supplies a page's top blank, so no second is added.
  testthat::expect_match(source, "needs_top = row_role ne 'spacer'", fixed = TRUE)

  # Capacity zero must stay available as "no page breaking at all".
  disabled <- header
  disabled$page_rows <- 0L
  off <- page_break_source(disabled)
  testthat::expect_match(paste(off, collapse = "\n"),
                         "disabled for this header", fixed = TRUE)
  testthat::expect_identical(sum(grepl("page_group = 1", off, fixed = TRUE)), 1L)
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

  # The default is implicit, so it must not appear in the rendered YAML; emitting
  # it would change the bytes of every existing bundle.
  testthat::expect_false(grepl("page_rows", canonical_yaml_text(build()), fixed = TRUE))
  testthat::expect_true(grepl("page_rows: 18", canonical_yaml_text(build(18L)), fixed = TRUE))

  # Zero means "never break"; a negative capacity is not a page.
  zero <- parse_bundle_yaml(canonical_yaml_text(build(0L)))
  testthat::expect_true(zero$passed)
  testthat::expect_identical(zero$workspace$headers[[1L]]$page_rows, 0L)
  # A negative capacity is rejected at the model boundary; encoding refuses to
  # emit it at all, so assert that refusal rather than a round trip.
  testthat::expect_error(canonical_yaml_text(build(-1L)), "invalid metadata bundle")
})
