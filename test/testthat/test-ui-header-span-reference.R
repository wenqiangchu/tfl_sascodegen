source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)

# The header editor shows spanning headers as text in two extra columns and rebuilds
# the spanning_headers collection from those labels: consecutive equal labels become one
# span, empty labels produce none, and span ids are renumbered by position. That is fine
# for the labels, but it discards information the user never touched.
#
# Q8 decided the rebuild must keep the original spans by reference: an untouched header
# keeps its original span objects, including their ids, and an edit changes only the
# spans the edit actually affects. Span ids are referenced from column
# spanning_header_1 / spanning_header_2, so renumbering them is a real change to the
# data, not formatting -- and the untouched-header case must not look edited at all.
span_bundle_header <- function() {
  columns <- lapply(1:4, function(index) list(
    id = paste0("c", index), label = paste0("Column ", index), condition = "1",
    display_order = as.integer(index), width = 1, alignment = "center"
  ))
  # Two level-1 spans and one level-2 span, with ids that carry meaning rather than
  # position, so renumbering is visible.
  columns[[1L]]$spanning_header_1 <- "safety"
  columns[[2L]]$spanning_header_1 <- "safety"
  columns[[3L]]$spanning_header_1 <- "efficacy"
  columns[[4L]]$spanning_header_1 <- "efficacy"
  columns[[1L]]$spanning_header_2 <- "low_dose"
  columns[[2L]]$spanning_header_2 <- "low_dose"
  list(
    id = "h", source_data = "&lib..adsl", orientation = "landscape",
    page_rows = default_page_rows,
    spanning_headers = list(
      list(id = "safety", level = 1L, label = "Safety"),
      list(id = "efficacy", level = 1L, label = "Efficacy"),
      list(id = "low_dose", level = 2L, label = "Low dose")
    ),
    columns = columns
  )
}

collect <- function(header, data = header_editor_data(header)) {
  header_from_editor_data(header$id, header$source_data, data, header$orientation,
                          original = header)
}

testthat::test_that("an untouched header keeps its original span ids by reference", {
  original <- span_bundle_header()
  collected <- collect(original)
  testthat::expect_identical(collected, original)
  # The ids specifically, since that is what renumbering destroyed.
  testthat::expect_identical(
    vapply(collected$spanning_headers, `[[`, character(1L), "id"),
    c("safety", "efficacy", "low_dose")
  )
})

testthat::test_that("renaming one span replaces only that span", {
  original <- span_bundle_header()
  data <- header_editor_data(original)
  # Rename the first level-1 span only. A label that no longer matches its original
  # columns is a different span, so it gets a new id; what matters is that the spans the
  # edit did not touch keep theirs.
  data$spanning_header_1[data$spanning_header_1 == "Safety"] <- "Safety population"
  collected <- collect(original, data)
  ids <- vapply(collected$spanning_headers, `[[`, character(1L), "id")
  labels <- setNames(vapply(collected$spanning_headers, `[[`, character(1L), "label"), ids)
  testthat::expect_true("Safety population" %in% labels)
  testthat::expect_false("Safety" %in% labels)
  # Untouched spans keep their identity.
  testthat::expect_true("efficacy" %in% ids)
  testthat::expect_true("low_dose" %in% ids)
  testthat::expect_identical(labels[["efficacy"]], "Efficacy")
  testthat::expect_identical(labels[["low_dose"]], "Low dose")
  # The renamed span's columns all point at the new span, and no dangling reference
  # remains to the old one.
  testthat::expect_identical(collected$columns[[1L]]$spanning_header_1,
                             collected$columns[[2L]]$spanning_header_1)
  testthat::expect_false(identical(collected$columns[[1L]]$spanning_header_1, "safety"))
})

testthat::test_that("clearing a span label removes only that span", {
  original <- span_bundle_header()
  data <- header_editor_data(original)
  data$spanning_header_1[data$spanning_header_1 == "Safety"] <- ""
  collected <- collect(original, data)
  ids <- vapply(collected$spanning_headers, `[[`, character(1L), "id")
  testthat::expect_false("safety" %in% ids)
  # The surviving spans keep their identity, and the cleared columns carry no span
  # reference (the field is absent, as it is on any column without a spanning header).
  testthat::expect_true(all(c("efficacy", "low_dose") %in% ids))
  testthat::expect_null(collected$columns[[1L]]$spanning_header_1)
  testthat::expect_null(collected$columns[[2L]]$spanning_header_1)
})

testthat::test_that("a new span gets a fresh id that collides with nothing", {
  original <- span_bundle_header()
  data <- header_editor_data(original)
  # Give the first two columns a label no existing span carries.
  data$spanning_header_1[seq_len(2L)] <- "New group"
  collected <- collect(original, data)
  ids <- vapply(collected$spanning_headers, `[[`, character(1L), "id")
  testthat::expect_equal(sum(duplicated(ids)), 0L)
  labels <- setNames(vapply(collected$spanning_headers, `[[`, character(1L), "label"), ids)
  testthat::expect_true("New group" %in% labels)
  # Untouched spans survive with their ids.
  testthat::expect_true(all(c("efficacy", "low_dose") %in% ids))
})
