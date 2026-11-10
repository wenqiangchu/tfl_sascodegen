# result_sort.column_order must never crash the importer.
#
# column_order is a sequence, and each element is parsed with parse_integer_value(),
# which records an error and returns NULL for an invalid value. It used to be parsed
# inside vapply(), so a single bad element aborted the whole call with
#
#   values must be length 1, but FUN(X[[1]]) result is length 0
#
# That R error escaped parse_bundle_value() all the way to the Shiny import
# observer, so instead of an error envelope the user got a dead session -- and the
# workspace lives in memory, so unsaved edits were lost with it. Every other
# invalid field returns a structured error; this one has to as well.

result_sort_bundle <- function(column_order) {
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl", orientation = "landscape",
                        columns = list(
                          list(id = "all", label = "All", condition = "1",
                               display_order = 1L, width = 1, alignment = "center")
                        ))),
    tables = list(list(id = "t1", population_id = "p", header_id = "h",
                       template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = list(list(
      id = "hier", type = "hierarchical_summary", source_data = "adam.adae",
      levels = list(
        list(id = "l1", variable = "SOC", order_variable = "SOCN",
             order_direction = "asc", node_role = "analysis",
             node_analysis_id = "a1", missing_policy = "exclude",
             result_sort = list(
               metric = list(analysis_id = "a1", row_id = "r1", statistic_id = "mean"),
               column_order = column_order, direction = "desc")),
        list(id = "l2", variable = "PT", order_variable = "PTN",
             order_direction = "asc", node_role = "label", missing_policy = "exclude")
      ),
      # The level points at this block via node_analysis_id, so the contract
      # requires it to be a same_row block anchored at that level.
      analysis_blocks = list(list(
        id = "a1", anchor_level = "l1", placement = "same_row",
        type = "continuous_summary", counting_unit = "record",
        analysis_variable = "AGE", rows = list(list(
          id = "r1", type = "analysis", label = "Mean",
          statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
        ))
      ))
    )))))
  )
}

testthat::test_that("an invalid column_order element is an error envelope, not an R error", {
  # -1 is below min_value, 1.5 is not integral, "x" is not numeric, NA is missing,
  # 1e10 is above the integer range. All five used to abort inside vapply().
  for (bad in list(-1, 1.5, "x", NA_real_, 1e10)) {
    label <- format(bad)
    parsed <- NULL
    testthat::expect_no_error(
      parsed <- parse_bundle_value(result_sort_bundle(list(bad))))
    testthat::expect_true(length(parsed$errors) > 0L, label = label)
    testthat::expect_true(
      any(grepl("column_order", vapply(parsed$errors, `[[`, "", "path"))),
      label = label)
  }
})

testthat::test_that("a bad element in a longer column_order is also reported, not thrown", {
  # The failing element is not the first, so this covers the general loop rather
  # than only the leading position.
  parsed <- NULL
  testthat::expect_no_error(parsed <- parse_bundle_value(result_sort_bundle(list(1L, -1))))
  testthat::expect_true(length(parsed$errors) > 0L)
  testthat::expect_true(
    any(grepl("column_order", vapply(parsed$errors, `[[`, "", "path"))))
})

testthat::test_that("column_order keeps its own rules when every element is valid", {
  # Uniqueness and "zero at most once, and only at the end" must still run; a fix
  # that skipped straight to returning NULL on any trouble would silently drop them.
  duplicate <- parse_bundle_value(result_sort_bundle(list(1L, 1L)))
  testthat::expect_true(length(duplicate$errors) > 0L)
  testthat::expect_true(any(grepl("must be unique",
                                  vapply(duplicate$errors, `[[`, "", "message"))))

  early_zero <- parse_bundle_value(result_sort_bundle(list(0L, 1L)))
  testthat::expect_true(length(early_zero$errors) > 0L)
  testthat::expect_true(any(grepl("zero may occur at most once",
                                  vapply(early_zero$errors, `[[`, "", "message"))))

  # A valid sequence still parses, with integer type preserved for round trips.
  valid <- parse_bundle_value(result_sort_bundle(list(1L, 0L)))
  testthat::expect_identical(valid$errors, list())
  chunk <- valid$value$templates[[1L]]$body$chunks[[1L]]
  testthat::expect_identical(chunk$levels[[1L]]$result_sort$column_order, c(1L, 0L))
})

testthat::test_that("the ZIP import path returns an envelope for a bad column_order", {
  # The regression was only visible through the real transport: parse_bundle_value()
  # is also called directly by tests, so asserting it alone would not prove that
  # application_import_bundle() survives. This exports canonical bytes, corrupts one
  # element in the template entry and imports the archive again.
  skip_if_not_installed("zip")
  parsed <- parse_bundle_value(result_sort_bundle(list(1L)))
  testthat::expect_identical(parsed$errors, list())

  work <- tempfile("result-sort-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE, force = TRUE), add = TRUE)

  archive <- file.path(work, "bundle.zip")
  writeBin(as.raw(canonical_archive_bytes(parsed$value)$bytes), archive)
  zip::unzip(archive, exdir = file.path(work, "entries"))

  template_file <- list.files(file.path(work, "entries", "templates"),
                              full.names = TRUE)[1L]
  lines <- readLines(template_file, warn = FALSE)
  element <- grep("^ +- 1$", lines)
  testthat::expect_length(element, 1L)
  lines[element] <- sub("- 1$", "- -1", lines[element])
  writeLines(lines, template_file)

  corrupted <- file.path(work, "corrupted.zip")
  previous <- setwd(file.path(work, "entries"))
  on.exit(setwd(previous), add = TRUE)
  # mode = "mirror" keeps the entry paths relative to the archive root; without it
  # the entries get a directory prefix and the importer rejects them as unsupported.
  zip::zipr(corrupted, files = list.files(".", recursive = TRUE), mode = "mirror")
  setwd(previous)

  result <- NULL
  testthat::expect_no_error(
    result <- application_import_bundle(
      new_empty_workspace(),
      readBin(corrupted, "raw", file.info(corrupted)$size)))
  testthat::expect_false(result$passed)
  testthat::expect_true(length(result$errors) > 0L)
  testthat::expect_true(
    any(grepl("column_order", vapply(result$errors, `[[`, "", "path"))))
})
