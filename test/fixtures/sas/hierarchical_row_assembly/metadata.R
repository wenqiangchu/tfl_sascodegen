# Pure synthetic metadata and hand-calculated expected rows; no SAS execution.
row_assembly_fixture <- function(case = "basic") {
  stopifnot(case %in% c("basic", "sorted", "multilevel", "mixed", "empty"))
  mean_row <- function(label) list(
    id = "row", type = "analysis", label = label,
    statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}"
  )
  blocks <- lapply(c("node", "below"), function(id) list(
    id = id, anchor_level = "group", placement = if (id == "node") "same_row" else "below",
    type = "continuous_summary", counting_unit = "record",
    analysis_variable = if (id == "node") "VALUE1" else "VALUE2",
    rows = list(mean_row("Mean 2"))
  ))
  chunk <- list(
    id = "hier", type = "hierarchical_summary", source_data = "work.ra_records",
    source_contract = list(grain = "record", subject_key = "USUBJID",
      record_key = c("USUBJID", "SEQ"), duplicate_policy = "error"),
    levels = list(list(id = "group", variable = "GROUP_VALUE", order_variable = "GROUPN",
      order_direction = "asc", node_role = "analysis", node_analysis_id = "node",
      missing_policy = "exclude")),
    analysis_blocks = blocks
  )
  if (case %in% c("sorted", "multilevel")) {
    chunk$levels[[1L]]$result_sort <- list(
      metric = list(analysis_id = "below", row_id = "row", statistic_id = "mean"),
      column_order = c(1L, 0L), direction = "desc"
    )
  }
  if (case == "multilevel") {
    chunk$levels[[1L]]$node_role <- "label"
    chunk$levels[[1L]]$node_analysis_id <- NULL
    chunk$levels[[2L]] <- list(
      id = "detail", variable = "CHILD_VALUE", order_variable = "CHILDN",
      order_direction = "asc", node_role = "analysis", node_analysis_id = "child",
      missing_policy = "exclude"
    )
    below <- blocks[[2L]]
    below$rows <- c(list(list(id = "heading", type = "label", label = "Summary")), below$rows)
    chunk$analysis_blocks <- list(below, list(
      id = "child", anchor_level = "detail", placement = "same_row",
      type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
      denominator = list(scope = "current_group", unit = "distinct_subject"),
      rows = list(list(id = "row", type = "analysis", label = "Subjects", condition = "1",
        statistics = list(list(id = "n")), cell_format = "{n}"))
    ))
  }
  if (case == "empty") chunk$filter <- "0"
  chunks <- list(chunk)
  if (case == "mixed") {
    second <- chunk
    second$id <- "hier2"
    chunks <- list(chunk, list(
      id = "overall", type = "continuous_summary", source_data = "work.ra_adsl",
      analysis_variable = "VALUE1", rows = list(mean_row("Overall"))
    ), second)
  }
  new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(list(id = "h", source_data = "work.ra_adsl", orientation = "landscape",
      columns = lapply(1:3, function(index) list(
        id = c("overall", "subset", "empty")[[index]],
        label = c("Overall", "Subset", "Empty")[[index]],
        condition = c("1", "USUBJID = '01'", "0")[[index]],
        display_order = index, width = 1, alignment = "center"
      )))),
    tables = list(list(id = "ra", population_id = "p", header_id = "h", template_id = "t")),
    templates = list(list(id = "t", body = list(chunks = chunks)))
  )
}

row_assembly_expected <- function(case = "basic") {
  # These values are independent of generator output and paired execution.
  # Basic: A -> (2+4)/2 and (12+14)/2; B -> (10+20)/2 and (110+120)/2.
  basic <- paste(
    "row|A|0|dynamic|1|3:C:A|5:3:C:A4:node3:row|3.0|2.0|NE",
    "row|Mean 2|1|static|1|3:C:A|5:3:C:A5:below3:row|13.0|12.0|NE",
    "row|B|0|dynamic|1|3:C:B|5:3:C:B4:node3:row|15.0|10.0|NE",
    "row|Mean 2|1|static|1|3:C:B|5:3:C:B5:below3:row|115.0|110.0|NE",
    sep = "\n"
  )
  multilevel <- paste(
    "group|B|0|dynamic|1|3:C:B|5:3:C:B:label|||",
    "heading|Summary|1|static|1|3:C:B|5:3:C:B5:below7:heading|||",
    "row|Mean 2|1|static|1|3:C:B|5:3:C:B5:below3:row|115.0|110.0|NE",
    "row|X|1|dynamic|2|3:C:B3:C:X|10:3:C:B3:C:X5:child3:row|1|1|0",
    "row|Y|1|dynamic|2|3:C:B3:C:Y|10:3:C:B3:C:Y5:child3:row|1|0|0",
    "group|A|0|dynamic|1|3:C:A|5:3:C:A:label|||",
    "heading|Summary|1|static|1|3:C:A|5:3:C:A5:below7:heading|||",
    "row|Mean 2|1|static|1|3:C:A|5:3:C:A5:below3:row|13.0|12.0|NE",
    "row|X|1|dynamic|2|3:C:A3:C:X|10:3:C:A3:C:X5:child3:row|1|1|0",
    "row|Y|1|dynamic|2|3:C:A3:C:Y|10:3:C:A3:C:Y5:child3:row|1|0|0",
    sep = "\n"
  )
  read_rows <- function(text) utils::read.table(
    text = text, sep = "|", quote = "", comment.char = "", colClasses = "character",
    col.names = c("row_id", "label", "indent_level", "row_role", "hierarchy_level",
      "node_key", "runtime_row_id", "col_001", "col_002", "col_003")
  )
  rows <- read_rows(if (case == "multilevel") multilevel else basic)
  if (case == "sorted") rows <- rows[c(3L, 4L, 1L, 2L), ]
  rows$chunk_id <- "hier"
  rows$chunk_order <- 1L
  rows$row_sequence <- seq_len(nrow(rows))
  if (case == "mixed") {
    middle <- read_rows("row|Overall|0|analysis|0||row|3.0|2.0|NE")
    middle$chunk_id <- "overall"
    middle$chunk_order <- 2L
    middle$row_sequence <- 1L
    second <- rows
    second$chunk_id <- "hier2"
    second$chunk_order <- 3L
    rows <- rbind(rows, middle, second)
  }
  if (case == "empty") rows <- rows[FALSE, ]
  rows$indent_level <- as.integer(rows$indent_level)
  rows$hierarchy_level <- as.integer(rows$hierarchy_level)
  rownames(rows) <- NULL
  rows
}
