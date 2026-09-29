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
