source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# A same_row block renders on the level's own node row, so all of its rows share one
# order_key: hierarchical.R emits
#   order_key = cats(display_order_path, 'A')
# with no row_order, and the flattening step then does
#   by order_key; if first.order_key then row_sequence + 1;
# so every row of the block lands on one row_sequence. The wide pivot addresses a
# cell by (row_sequence, column_order), so the rows overwrite each other and only the
# last one survives -- silently, because nothing downstream expects a second row.
#
# Q4 decided this: a same_row block holds exactly one row. Multiple rows are not a
# rendering case to design, they are a bundle that cannot be rendered faithfully, so
# the model rejects them at parse time instead of dropping data at run time.
same_row_bundle <- function(row_count) {
  rows <- lapply(seq_len(row_count), function(index) list(
    id = sprintf("r%d", index), type = "analysis",
    label = sprintf("Statistic %d", index),
    statistics = list(list(id = "n")), cell_format = "{n}"
  ))
  list(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adae",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "O", condition = "1",
                                            display_order = 1L, width = 1,
                                            alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(stub_header = "S", chunks = list(list(
      id = "k1", type = "hierarchical_summary", source_data = "adam.adae",
      levels = list(list(id = "l1", variable = "SOC", order_variable = "SOC",
                         order_direction = "asc", node_role = "analysis",
                         node_analysis_id = "a1", missing_policy = "exclude")),
      analysis_blocks = list(list(
        id = "a1", anchor_level = "l1", placement = "same_row",
        type = "continuous_summary",
        counting_unit = "record", analysis_variable = "AVAL",
        rows = rows
      ))
    ))))))
}

testthat::test_that("a same_row block accepts exactly one row", {
  single <- parse_bundle_value(do.call(new_metadata_bundle, same_row_bundle(1L)))
  testthat::expect_identical(single$errors, list())

  for (count in c(2L, 3L)) {
    many <- parse_bundle_value(do.call(new_metadata_bundle, same_row_bundle(count)))
    testthat::expect_true(length(many$errors) > 0L, label = as.character(count))
    codes <- vapply(many$errors, function(x) x$code, "")
    paths <- vapply(many$errors, function(x) x$path, "")
    testthat::expect_true(any(nzchar(paths) & grepl("analysis_blocks", paths)),
                          label = as.character(count))
    testthat::expect_true(length(codes) > 0L)
  }
})

testthat::test_that("the same_row row limit does not apply to below blocks", {
  # A below block renders as its own static rows under the node, and its order_key
  # carries both block_order and row_order, so several rows are a supported case.
  bundle <- same_row_bundle(3L)
  hierarchy <- bundle$templates[[1L]]$body$chunks[[1L]]
  hierarchy$analysis_blocks[[1L]]$placement <- "below"
  hierarchy$levels[[1L]]$node_role <- "label"
  hierarchy$levels[[1L]]$node_analysis_id <- NULL
  bundle$templates[[1L]]$body$chunks[[1L]] <- hierarchy
  parsed <- parse_bundle_value(do.call(new_metadata_bundle, bundle))
  testthat::expect_identical(parsed$errors, list())
})
