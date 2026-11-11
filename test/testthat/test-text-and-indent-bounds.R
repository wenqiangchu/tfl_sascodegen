source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# SAS character variables cap at 32767 bytes. report_text_lengths_source() sized the
# LENGTH statements from the metadata with max(32L, nchar(...)) and max(256L, ...),
# so a longer label or cell_format produced an illegal LENGTH statement that only
# failed inside SAS. The hierarchical emitter already capped itself; the primitive
# path did not.
text_bundle <- function(row_label = "L", stub_label = "S", cell_format = "{mean}") {
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(list(id = "t1", population_id = "p1", header_id = "h",
                       template_id = "t1")),
    templates = list(list(id = "t1", body = list(stub_header = stub_label,
      chunks = list(list(id = "k1", type = "continuous_summary",
        source_data = "adam.adsl", counting_unit = "record",
        analysis_variable = "AVAL",
        rows = list(list(id = "r1", type = "analysis", label = row_label,
                         cell_format = cell_format,
                         statistics = list(list(id = "mean", digits = 1L))))))))))
}

# A resolved table is what report_text_lengths_source() consumes: it reads the
# template and header and walks their text fields.
resolved_for <- function(template, header) list(template = template, header = header)

# The generated LENGTH values must never exceed the SAS character limit.
max_rendered_length <- function(resolved) {
  lines <- report_text_lengths_source(resolved)
  values <- suppressWarnings(as.integer(sub("^.*=([0-9]+);$", "\\1", lines[grepl("_LEN=", lines)])))
  max(values, na.rm = TRUE)
}

testthat::test_that("reported LENGTH values are capped at the SAS character limit", {
  huge <- strrep("x", 40000)
  resolved <- resolved_for(
    list(id = "t1", body = list(stub_header = huge, chunks = list(list(
      id = "k1", type = "continuous_summary", labels = list(huge),
      rows = list(list(id = "r1", type = "analysis", label = huge,
                       cell_format = huge, statistics = list(list(id = "mean")))))))),
    list(id = "h", columns = list(list(id = huge, label = huge)))
  )
  # 32767 is the SAS character variable maximum; anything above it produces an
  # illegal LENGTH statement that only fails inside SAS.
  testthat::expect_identical(max_rendered_length(resolved), 32767L)

  # Normal text keeps its exact size, so the cap does not inflate every program.
  small <- resolved_for(
    list(id = "t1", body = list(stub_header = "S", chunks = list())),
    list(id = "h", columns = list(list(id = "c1", label = "O")))
  )
  testthat::expect_identical(max_rendered_length(small), 256L)
})

testthat::test_that("text longer than the SAS character limit is refused", {
  at_limit <- parse_bundle_value(
    do.call(new_metadata_bundle, text_bundle(row_label = strrep("x", 32767))))
  testthat::expect_identical(at_limit$errors, list())

  over <- parse_bundle_value(
    do.call(new_metadata_bundle, text_bundle(row_label = strrep("x", 32768))))
  testthat::expect_true(length(over$errors) > 0L)
  paths <- vapply(over$errors, function(x) x$path, "")
  testthat::expect_true(any(grepl("label", paths)))
})

testthat::test_that("indent_level is bounded so indentation cannot overrun the page", {
  make <- function(indent) {
    bundle <- text_bundle()
    bundle$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$indent_level <- indent
    bundle
  }
  for (value in c(0L, 9L)) {
    parsed <- parse_bundle_value(do.call(new_metadata_bundle, make(value)))
    testthat::expect_identical(parsed$errors, list(), label = as.character(value))
  }
  for (value in c(10L, 100L)) {
    parsed <- parse_bundle_value(do.call(new_metadata_bundle, make(value)))
    testthat::expect_true(length(parsed$errors) > 0L, label = as.character(value))
    paths <- vapply(parsed$errors, function(x) x$path, "")
    testthat::expect_true(any(grepl("indent_level", paths)), label = as.character(value))
  }
})
