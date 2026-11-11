source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# A table id becomes three physical names: the ZIP entry "tables/<id>.yaml", the RTF
# file "<id>.rtf", and the SAS member "tables.<id>" used by PROC COMPARE. A template
# id becomes the ZIP entry "templates/<id>.yaml". Anything outside a file-safe
# character set, or longer than the 32-byte SAS member name limit, therefore exports
# successfully and then cannot be read back or cannot be referenced.
#
# The restriction is deliberately scoped to these two ids. Every other id (chunk,
# level, block, row, column, span) is either renumbered by the workspace or used only
# as an in-memory key, so requiring a file-safe form there would reject bundles that
# work today.
id_bundle <- function(table_id = "t1", template_id = "t1", chunk_id = "k1")
{
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(list(id = table_id, population_id = "p1", header_id = "h",
                       template_id = template_id)),
    templates = list(list(id = template_id, body = list(stub_header = "S",
      chunks = list(list(id = chunk_id, type = "continuous_summary",
        source_data = "adam.adsl", counting_unit = "record",
        analysis_variable = "AVAL",
        rows = list(list(id = "r1", type = "analysis", label = "L",
                         cell_format = "{mean}",
                         statistics = list(list(id = "mean", digits = 1L))))))))))
}

parse_ids <- function(...) {
  parse_bundle_value(do.call(new_metadata_bundle, id_bundle(...)))
}

path_has <- function(result, fragment) {
  paths <- vapply(result$errors, function(x) x$path, "")
  any(grepl(fragment, paths, fixed = TRUE))
}

testthat::test_that("file-safe table and template ids are accepted", {
  for (id in c("t1", "t_14_1_1_disposition", "a.b-c", "ABC_123",
               strrep("x", 32L))) {
    parsed <- parse_ids(table_id = id, template_id = id)
    testthat::expect_identical(parsed$errors, list(), label = id)
  }
})

testthat::test_that("a table id that cannot become a file name is refused", {
  # "/" makes the exported ZIP entry "tables/a/b.yaml", which the importer rejects as
  # an unsupported entry, so the bundle cannot round-trip.
  for (id in c("a/b", "a\\b", "a b", "a:b", "a*b", "a?b", "a|b", "a<b", "a>b")) {
    parsed <- parse_ids(table_id = id)
    testthat::expect_true(length(parsed$errors) > 0L, label = id)
    testthat::expect_true(path_has(parsed, "id"), label = id)
  }
})

testthat::test_that("an over-long table or template id is refused at the SAS member limit", {
  accepted <- parse_ids(table_id = strrep("x", 32L), template_id = strrep("y", 32L))
  testthat::expect_identical(accepted$errors, list())

  for (id in c(strrep("x", 33L), strrep("x", 100L))) {
    long_table <- parse_ids(table_id = id)
    testthat::expect_true(length(long_table$errors) > 0L)
    testthat::expect_true(path_has(long_table, "id"))

    long_template <- parse_ids(table_id = "t1", template_id = id)
    testthat::expect_true(length(long_template$errors) > 0L)
    testthat::expect_true(path_has(long_template, "id"))
  }
})

testthat::test_that("the file-safe rule does not reach ids that are only references or keys", {
  # chunk ids never become file names; the workspace renumbers them on save and the
  # emitter writes them as SAS character literals. A bundle using a spaced chunk id
  # works today, so it must keep working.
  spaced_chunk <- parse_ids(chunk_id = "chunk one")
  testthat::expect_identical(spaced_chunk$errors, list())

  # A column id is also only an in-memory key: report_column_names() turns positions
  # into col_NNN, so the user-facing id never reaches SAS.
  bundle <- id_bundle()
  bundle$headers[[1L]]$columns[[1L]]$id <- "column one"
  parsed <- parse_bundle_value(do.call(new_metadata_bundle, bundle))
  testthat::expect_identical(parsed$errors, list())
})
