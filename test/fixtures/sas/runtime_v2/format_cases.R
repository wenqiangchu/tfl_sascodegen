# Synthetic formats and literal expected subject counts, independent of emitters.
format_case <- function(case) {
  header <- list(id = "h", source_data = "work.rv_adsl", orientation = "landscape",
    columns = lapply(seq_len(3L), function(i) list(
      id = c("all", "subset", "empty")[[i]], label = c("All", "Subset", "Empty")[[i]],
      condition = c("1", "USUBJID='01'", "0")[[i]], display_order = i,
      width = 1, alignment = "center")))
  block <- function(id, anchor) list(id = id, anchor_level = anchor, placement = "same_row",
    type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
    denominator = list(scope = "header_population", unit = "distinct_subject"),
    rows = list(list(id = "count", type = "analysis", label = "Subjects", condition = "1",
      statistics = list(list(id = "n"), list(id = "pct", digits = 1L)), cell_format = "{n}|{pct}")))
  levels <- list(
    list(id = "visit", variable = "VISIT", format = "rvvisit", node_role = "analysis",
         node_analysis_id = "visits", missing_policy = "exclude"),
    list(id = "category", variable = "CAT", format = "$rvcat", node_role = "analysis",
         node_analysis_id = "categories", missing_policy = "exclude"))
  before <- c(
    "data work.rv_adsl; length USUBJID $2; input USUBJID $; datalines;", "01", "02", "03", ";", "run;",
    "proc format; value rvvisit (notsorted) 2='Week 2' 1='Week 1' 3='Week 3';",
    "  value $rvcat (notsorted) 'C'='High' 'A','B'='Low' 'D'='Rare'; run;",
    "data work.rv_events; length USUBJID $2 CAT THIRD $1; input USUBJID $ VISIT CAT $ THIRD $; datalines;",
    "01 1 A X", "01 1 B Y", "02 1 C X", "01 2 C X", "03 2 . X", ";", "run;"
  )
  if (case %in% c("empty", "empty_label", "empty_error")) {
    before <- c(before, "data work.rv_events; set work.rv_events; stop; run;")
    if (case != "empty") for (i in 1:2) {
      levels[[i]]$missing_policy <- if (case == "empty_label") "label" else "error"
      if (case == "empty_label") levels[[i]]$missing_label <- "Missing"
    }
  }
  if (case == "reversed") before <- c(before,
    "data work.rv_events; set work.rv_events; seq=_n_; run;",
    "proc sort data=work.rv_events; by descending seq; run;")
  if (case == "duplicated") before <- c(before, "data work.rv_events; set work.rv_events work.rv_events; run;")
  if (case %in% c("missing_label", "missing_error")) {
    levels[[2L]]$missing_policy <- if (case == "missing_label") "label" else "error"
    if (case == "missing_label") levels[[2L]]$missing_label <- "Missing"
  }
  if (case == "sorted") levels[[2L]]$result_sort <- list(
    metric = list(analysis_id = "categories", row_id = "count", statistic_id = "n"),
    column_order = c(1L, 0L), direction = "asc")
  blocks <- list(block("visits", "visit"), block("categories", "category"))
  if (case == "third_level") {
    levels[[3L]] <- list(id = "third", variable = "THIRD", order_variable = "THIRD",
                        order_direction = "asc", node_role = "analysis",
                        node_analysis_id = "thirds", missing_policy = "exclude")
    blocks[[3L]] <- block("thirds", "third")
  }
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p", label = "Population", expression = "1")),
    headers = list(header),
    tables = list(list(id = paste0("rv_", case), population_id = "p", header_id = "h",
                       template_id = "t", custom_code = list(before = paste(before, collapse = "\n")))),
    templates = list(list(id = "t", body = list(stub_header = "Visit / category", chunks = list(
      list(id = "h", type = "hierarchical_summary", source_data = "work.rv_events",
           levels = levels, analysis_blocks = blocks))))))

  # Literal expected counts: [All, subject 01 subset, empty column]. A and B
  # both map to Low, so their two records count as one subject within the node.
  counts <- list(
    "Week 2" = c(2, 1, 0), "Week 1" = c(2, 1, 0), "Week 3" = c(0, 0, 0),
    "Week 2/High" = c(1, 1, 0), "Week 2/Low" = c(0, 0, 0), "Week 2/Rare" = c(0, 0, 0),
    "Week 1/High" = c(1, 0, 0), "Week 1/Low" = c(1, 1, 0), "Week 1/Rare" = c(0, 0, 0),
    "Week 3/High" = c(0, 0, 0), "Week 3/Low" = c(0, 0, 0), "Week 3/Rare" = c(0, 0, 0))
  if (case %in% c("empty", "empty_label", "empty_error")) counts <- lapply(counts, function(x) c(0, 0, 0))
  if (case == "missing_label") counts[["Week 2/Missing"]] <- c(1, 0, 0)
  if (case == "third_level") counts <- c(counts, list(
    "Week 2/High/X" = c(1, 1, 0), "Week 1/High/X" = c(1, 0, 0),
    "Week 1/Low/X" = c(1, 1, 0), "Week 1/Low/Y" = c(1, 1, 0)))
  expected_order <- character()
  for (parent in c("Week 2", "Week 1", "Week 3")) {
    expected_order <- c(expected_order, parent)
    children <- c("High", "Low", "Rare")
    if (case == "sorted") children <- children[order(
      vapply(children, function(child) counts[[paste(parent, child, sep = "/")]][[1L]], 0), children)]
    for (child in children) {
      path <- paste(parent, child, sep = "/")
      expected_order <- c(expected_order, path)
      if (case == "third_level") {
        candidates <- paste(path, c("X", "Y"), sep = "/")
        expected_order <- c(expected_order, candidates[candidates %in% names(counts)])
      }
    }
  }
  if (case == "unformatted_order") {
    for (i in 1:2) {
      bundle$templates[[1L]]$body$chunks[[1L]]$levels[[i]]$format <- NULL
      bundle$templates[[1L]]$body$chunks[[1L]]$levels[[i]]$order_variable <- c("VISIT", "RANK")[[i]]
      bundle$templates[[1L]]$body$chunks[[1L]]$levels[[i]]$order_direction <- c("desc", "asc")[[i]]
    }
    bundle$tables[[1L]]$custom_code$before <- paste(bundle$tables[[1L]]$custom_code$before,
      "data work.rv_events; set work.rv_events; RANK=index('BCA',CAT); run;", sep = "\n")
    counts <- list("2" = c(2,1,0), "2/C" = c(1,1,0), "1" = c(2,1,0),
                   "1/B" = c(1,1,0), "1/C" = c(1,0,0), "1/A" = c(1,1,0))
    expected_order <- names(counts)
  }
  if (case == "same_variable") {
    bundle$tables[[1L]]$custom_code$before <- paste(bundle$tables[[1L]]$custom_code$before,
      "proc format; value rvgroup (notsorted) 1,2='Active' 3='Future'; run;", sep = "\n")
    bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]]$variable <- "VISIT"
    bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]]$format <- "rvgroup"
    counts <- list("Week 2" = c(2,1,0), "Week 2/Active" = c(2,1,0), "Week 2/Future" = c(0,0,0),
                   "Week 1" = c(2,1,0), "Week 1/Active" = c(2,1,0), "Week 1/Future" = c(0,0,0),
                   "Week 3" = c(0,0,0), "Week 3/Active" = c(0,0,0), "Week 3/Future" = c(0,0,0))
    expected_order <- names(counts)
  }
  if (case == "long_labels") {
    replacements <- c("Week 2" = strrep("Visit", 140L), "High" = strrep("\u5206\u7c7b\u7532", 120L))
    replace_labels <- function(values) {
      for (label in names(replacements)) values <- gsub(label, replacements[[label]], values, fixed = TRUE)
      values
    }
    bundle$tables[[1L]]$custom_code$before <- replace_labels(bundle$tables[[1L]]$custom_code$before)
    names(counts) <- replace_labels(names(counts))
    expected_order <- replace_labels(expected_order)
    level <- bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]]
    level$missing_policy <- "label"
    level$missing_label <- strrep("Missing", 100L)
    bundle$templates[[1L]]$body$chunks[[1L]]$levels[[2L]] <- level
    counts[[paste(replacements[["Week 2"]], level$missing_label, sep = "/")]] <- c(1,0,0)
  }
  list(bundle = bundle, expected_counts = counts, expected_order = expected_order, header_n = c(3, 1, 0),
       expected_missing_warnings = if (case == "missing_error") 1L else 0L)
}
