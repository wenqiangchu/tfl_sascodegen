source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)

header_span_editor_fixture <- function() {
  columns <- lapply(1:4, function(index) list(
    id = paste0("c", index), label = paste0("Column ", index), condition = "1",
    display_order = index, width = 1, alignment = "center"
  ))
  columns[[1L]]$spanning_header_1 <- "treatment"
  columns[[2L]]$spanning_header_1 <- "treatment"
  columns[[4L]]$spanning_header_1 <- "second_treatment"
  columns[[1L]]$spanning_header_2 <- "dose"
  list(
    id = "header", source_data = "&lib..adsl", orientation = "landscape",
    # Header parsing always materialises the page capacity, so fixtures must
    # carry it too or every comparison looks like a user edit.
    page_rows = default_page_rows,
    spanning_headers = list(
      list(id = "treatment", level = 1L, label = "Treatment"),
      list(id = "second_treatment", level = 1L, label = "Treatment"),
      list(id = "dose", level = 2L, label = "Dose")
    ), columns = columns
  )
}

testthat::test_that("unchanged header collection preserves imported IDs and saved revision", {
  original <- header_span_editor_fixture()
  collected <- header_from_editor_data(original$id, original$source_data,
                                       header_editor_data(original), original$orientation,
                                       original = original)
  testthat::expect_identical(collected, original)
  workspace <- new_metadata_workspace(new_metadata_bundle(headers = list(original)))
  saved <- workspace_update(workspace, workspace_target("header", original$id), collected)
  testthat::expect_true(saved$passed)
  testthat::expect_identical(saved$workspace$revision$saved_revision,
                             workspace$revision$saved_revision)
  testthat::expect_identical(saved$workspace$headers, workspace$headers)
})

testthat::test_that("header edits remain dirty and reverting restores the original object", {
  original <- header_span_editor_fixture()
  for (field in c("label", "condition", "width", "alignment", "display_order",
                  "spanning_header_1", "spanning_header_2")) {
    data <- header_editor_data(original)
    previous <- data[[field]][[1L]]
    data[[field]][[1L]] <- switch(field, width = 2, display_order = 2L, "Edited")
    edited <- header_from_editor_data(original$id, original$source_data, data,
                                      original$orientation, original = original)
    testthat::expect_false(workspace_canonical_equal(edited, original), info = field)
    data[[field]][[1L]] <- previous
    restored <- header_from_editor_data(original$id, original$source_data, data,
                                        original$orientation, original = original)
    testthat::expect_identical(restored, original, info = field)
  }
  for (values in list(list(source = "work.changed", orientation = original$orientation),
                       list(source = original$source_data, orientation = "portrait"))) {
    edited <- header_from_editor_data(original$id, values$source, header_editor_data(original),
                                      values$orientation, original = original)
    testthat::expect_false(workspace_canonical_equal(edited, original))
  }
  removed <- header_from_editor_data(original$id, original$source_data,
                                     header_editor_data(original)[-4L, ], original$orientation,
                                     original = original)
  testthat::expect_false(workspace_canonical_equal(removed, original))
})

testthat::test_that("changed headers keep canonical field order and distinct label runs", {
  original <- header_span_editor_fixture()
  data <- header_editor_data(original)
  data$label[[1L]] <- "Edited column"
  edited <- header_from_editor_data(original$id, original$source_data, data,
                                    original$orientation, original = original)
  testthat::expect_identical(names(edited), names(original))
  testthat::expect_length(edited$spanning_headers, 3L)
  testthat::expect_false(identical(edited$columns[[1L]]$spanning_header_1,
                                  edited$columns[[4L]]$spanning_header_1))
  workspace <- new_metadata_workspace(new_metadata_bundle(headers = list(original)))
  saved <- workspace_update(workspace, workspace_target("header", original$id), edited)
  testthat::expect_true(saved$passed)
  header <- saved$workspace$headers[[1L]]
  testthat::expect_identical(header_from_editor_data(
    header$id, header$source_data, header_editor_data(header), header$orientation,
    original = header
  ), header)
})

testthat::test_that("the page capacity is editable and round-trips through the editor", {
  original <- header_span_editor_fixture()
  data <- header_editor_data(original)

  # The posted value wins over the stored one.
  lowered <- header_from_editor_data(original$id, original$source_data, data,
                                     original$orientation, page_rows = 18L,
                                     original = original)
  testthat::expect_identical(lowered$page_rows, 18L)

  # 0 is a real value ("do not paginate"), not "unset": it must survive the
  # conversion rather than fall back to the original.
  disabled <- header_from_editor_data(original$id, original$source_data, data,
                                      original$orientation, page_rows = 0L,
                                      original = original)
  testthat::expect_identical(disabled$page_rows, 0L)

  # An empty or not-yet-rendered control posts NULL/NA; the original value carries
  # over so an unrelated edit does not silently reset the capacity.
  untouched <- header_from_editor_data(original$id, original$source_data, data,
                                       original$orientation, page_rows = NULL,
                                       original = original)
  testthat::expect_identical(untouched$page_rows, original$page_rows)
  blank <- header_from_editor_data(original$id, original$source_data, data,
                                   original$orientation, page_rows = NA_integer_,
                                   original = original)
  testthat::expect_identical(blank, original)

  # Changing only the capacity is an edit, and reverting it is not.
  testthat::expect_false(workspace_canonical_equal(lowered, original))
  reverted <- header_from_editor_data(original$id, original$source_data, data,
                                      original$orientation,
                                      page_rows = original$page_rows, original = original)
  testthat::expect_identical(reverted, original)
})

testthat::test_that("the page capacity control is rendered and wired", {
  ui <- paste(readLines(file.path(project_root, "src", "ui", "metadata_editor_ui.R"),
                        warn = FALSE), collapse = "\n")
  testthat::expect_match(ui, "header_page_rows", fixed = TRUE)
  # The minimum has to agree with the parser, which refuses 1 and 2 because two
  # of every page's printed lines are the mandatory edge blanks.
  testthat::expect_match(ui, "min = 0", fixed = TRUE)
  testthat::expect_match(ui, "minimum is 4", fixed = TRUE)

  runtime <- paste(readLines(file.path(project_root, "src", "ui", "metadata_editor_runtime.R"),
                             warn = FALSE), collapse = "\n")
  # Collected on save and refreshed when another header is selected; missing
  # either half leaves the control showing a stale value.
  testthat::expect_match(runtime, "page_rows = input$header_page_rows", fixed = TRUE)
  testthat::expect_match(runtime, "updateNumericInput(session,\"header_page_rows\"",
                         fixed = TRUE)
})

testthat::test_that("a fractional page capacity is rejected instead of rounded", {
  original <- header_span_editor_fixture()
  data <- header_editor_data(original)

  # numericInput posts whatever was typed. Rounding it silently would save a
  # different number than the user entered, so a non-integral value must reach the
  # model intact and be rejected there by name.
  for (value in list(22.9, 2.9, 3.5)) {
    collected <- header_from_editor_data(original$id, original$source_data, data,
                                         original$orientation, page_rows = value,
                                         original = original)
    header <- collected
    errors <- parse_bundle_value(
      new_metadata_bundle(headers = list(header)))$errors
    testthat::expect_true(length(errors) > 0L, label = as.character(value))
    testthat::expect_true(
      any(grepl("page_rows", vapply(errors, `[[`, "", "path"))),
      label = as.character(value))
  }

  # An exact integer still saves, so the guard above is not blanket rejection.
  ok <- header_from_editor_data(original$id, original$source_data, data,
                                original$orientation, page_rows = 18,
                                original = original)
  testthat::expect_identical(ok$page_rows, 18L)
  testthat::expect_identical(parse_bundle_value(
    new_metadata_bundle(headers = list(ok)))$errors, list())

  # A value beyond the integer range is still a valid finite integer, so it is
  # carried as a double rather than coerced into NA. Wrapping it to NA would make
  # the model report a missing value instead of the number that was entered.
  huge <- header_from_editor_data(original$id, original$source_data, data,
                                  original$orientation, page_rows = 1e10,
                                  original = original)
  testthat::expect_false(is.na(huge$page_rows))
  testthat::expect_identical(as.numeric(huge$page_rows), 1e10)
})
