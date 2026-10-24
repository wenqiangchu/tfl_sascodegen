report_fixture <- function(orientation = "landscape") {
  new_metadata_bundle(
    populations = list(list(id = "safety", label = "Safety", expression = "SAFFL = 'Y'")),
    headers = list(list(
      id = "treatment", source_data = "adam.adsl", orientation = orientation,
      spanning_headers = list(list(id = "arms", level = 1L, label = "Treatment")),
      columns = list(
        list(id = "a", label = "Arm A", condition = "TRT01AN = 1", display_order = 1L,
             width = 1.25, alignment = "center", spanning_header_1 = "arms"),
        list(id = "all", label = "Overall", condition = "1", display_order = 2L,
             width = 1.5, alignment = "right", spanning_header_1 = "arms")
      )
    )),
    tables = list(list(
      id = "t_demog", population_id = "safety", header_id = "treatment", template_id = "demog",
      custom_code = list(
        before = "/* Project setup before population selection. */\n%let user_before = 1;",
        after = "/* Update the fixed report input. */\ndata WORK._TFL_ASM_001;\n  set WORK._TFL_ASM_001;\nrun;"
      )
    )),
    templates = list(list(id = "demog", body = list(stub_header = "Characteristic", chunks = list(
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl", analysis_variable = "AGE",
           rows = list(
             list(id = "heading", type = "label", label = "Age\\line (years)"),
             list(id = "mean_sd", type = "analysis", label = "Mean (SD)", indent_level = 1L,
                  statistics = list(list(id = "mean", digits = 1L), list(id = "sd", digits = 2L)),
                  cell_format = "{mean} ({sd})")
           ))
    ))))
  )
}

testthat::test_that("orientation is explicit and survives the metadata archive boundary", {
  for (orientation in c("portrait", "landscape")) {
    bundle <- report_fixture(orientation)
    parsed <- parse_bundle_value(bundle)
    testthat::expect_length(parsed$errors, 0L)
    imported <- parse_bundle_archive(canonical_archive_bytes(bundle)$bytes)
    testthat::expect_true(imported$passed)
    testthat::expect_identical(imported$workspace$headers[[1L]]$orientation, orientation)
  }
  missing <- report_fixture()
  missing$headers[[1L]]$orientation <- NULL
  errors <- parse_bundle_value(missing)$errors
  testthat::expect_true(any(vapply(errors, function(error) {
    identical(error$code, "bundle_required_field_missing") && grepl("orientation$", error$path)
  }, logical(1L))))
  invalid <- parse_bundle_value(report_fixture("diagonal"))$errors
  testthat::expect_true(any(grepl("orientation$", vapply(invalid, `[[`, "", "path"))))
})

testthat::test_that("RTF source preserves custom hooks around the fixed report input", {
  bundle <- report_fixture()
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  source <- result$source
  testthat::expect_true(startsWith(source, bundle$tables[[1L]]$custom_code$before))
  testthat::expect_match(source, bundle$tables[[1L]]$custom_code$after, fixed = TRUE)
  markers <- c("Project setup before", "Select the table population", "Assemble table rows",
               "Update the fixed report input", "ods rtf file='t_demog.rtf' style=rtf;",
               "proc report data=WORK._TFL_ASM_001", "ods rtf close;")
  positions <- vapply(markers, function(marker) regexpr(marker, source, fixed = TRUE)[[1L]], integer(1L))
  testthat::expect_true(all(positions > 0L))
  testthat::expect_true(all(diff(positions) > 0L))
  testthat::expect_true(endsWith(source, "ods rtf close;"))
  testthat::expect_identical(source, generate_table_source(bundle, "t_demog")$source)
})

testthat::test_that("Letter layout reserves both margins and honors header widths and alignment", {
  landscape <- generate_table_source(report_fixture("landscape"), "t_demog")$source
  portrait <- generate_table_source(report_fixture("portrait"), "t_demog")$source
  testthat::expect_match(landscape, "papersize=letter orientation=landscape", fixed = TRUE)
  testthat::expect_match(portrait, "papersize=letter orientation=portrait", fixed = TRUE)
  testthat::expect_match(landscape, "cellwidth=6.25in", fixed = TRUE)
  testthat::expect_match(portrait, "cellwidth=3.75in", fixed = TRUE)
  testthat::expect_match(landscape, "cellwidth=1.25in just=center", fixed = TRUE)
  testthat::expect_match(landscape, "cellwidth=1.5in just=right", fixed = TRUE)
  testthat::expect_match(landscape, "'Treatment'", fixed = TRUE)
})

testthat::test_that("report headers count membership and report rows preserve formatted cells", {
  source <- generate_table_source(report_fixture(), "t_demog")$source
  testthat::expect_match(source, "count(distinct USUBJID)", fixed = TRUE)
  testthat::expect_match(source, "(N = &_TFL_N_001)", fixed = TRUE)
  testthat::expect_match(source, "coalesce(n.header_n, 0)", fixed = TRUE)
  testthat::expect_match(source, "Age\\line (years)", fixed = TRUE)
  testthat::expect_match(source, "indent_level * 200", fixed = TRUE)
  testthat::expect_match(source, "fontweight=medium", fixed = TRUE)
  testthat::expect_match(source, "protectspecialchars=off", fixed = TRUE)
  testthat::expect_match(source, "if last.column_order then output;", fixed = TRUE)
  testthat::expect_match(source, "cell_text = TRANWRD(cell_text", fixed = TRUE)
  testthat::expect_match(source, "hierarchy_level ne previous_level", fixed = TRUE)
  testthat::expect_match(source, "chunk_order ne previous_chunk", fixed = TRUE)
})

testthat::test_that("Header editor orientation survives save and archive export", {
  source(file.path(project_root, "src", "ui", "metadata_editor_helpers.R"), local = FALSE)
  bundle <- report_fixture()
  header <- bundle$headers[[1L]]
  edited <- header_from_editor_data(header$id, header$source_data, header_editor_data(header), "portrait")
  workspace <- workspace_begin_draft(new_metadata_workspace(bundle), "header", header$id)$workspace
  workspace <- workspace_set_draft(workspace, edited)$workspace
  saved <- workspace_save_draft(workspace)
  testthat::expect_true(saved$passed)
  exported <- application_export_bundle(saved$workspace)
  testthat::expect_true(exported$passed)
  imported <- parse_bundle_archive(exported$value$bytes)
  testthat::expect_true(imported$passed)
  testthat::expect_identical(imported$workspace$headers[[1L]]$orientation, "portrait")
})

testthat::test_that("the downloadable demo explicitly includes orientation and both custom hooks", {
  archive <- file.path(project_root, "assets", "demo_metadata.zip")
  imported <- application_import_bundle(new_empty_workspace(), readBin(archive, "raw", file.info(archive)$size))
  testthat::expect_true(imported$passed)
  testthat::expect_setequal(vapply(imported$workspace$headers, function(header) header$orientation, ""),
                           c("portrait", "landscape"))
  for (table in imported$workspace$tables) {
    generated <- application_generate_source(imported$workspace, table$id)
    testthat::expect_true(generated$passed, info = table$id)
    testthat::expect_true(startsWith(generated$value, table$custom_code$before), info = table$id)
    testthat::expect_true(grepl(table$custom_code$after, generated$value, fixed = TRUE), info = table$id)
    testthat::expect_true(grepl(paste0("ods rtf file='", table$id, ".rtf'"), generated$value, fixed = TRUE), info = table$id)
  }
})

testthat::test_that("report width failure is atomic and long labels remain intact", {
  too_wide <- report_fixture("portrait")
  too_wide$headers[[1L]]$columns[[1L]]$width <- 6.5
  result <- generate_table_source(too_wide, "t_demog")
  testthat::expect_false(result$passed)
  testthat::expect_null(result$source)
  testthat::expect_identical(result$errors[[1L]]$code, "generation_contract_invalid")
  long <- report_fixture()
  label <- paste0(paste(rep("Long label ", 60L), collapse = ""), "\\line Final text")
  long$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$label <- label
  source <- generate_table_source(long, "t_demog")$source
  testthat::expect_true(grepl(label, source, fixed = TRUE))
  testthat::expect_true(grepl(paste0("%let _TFL_LABEL_LEN=", nchar(label, type = "bytes"), ";"), source, fixed = TRUE))
})

testthat::test_that("generation options control duplicate checks and report versus QC output", {
  bundle <- report_fixture()
  report <- generate_table_source(bundle, "t_demog", include_duplicate_check = TRUE,
                                  output_mode = "report")
  no_duplicates <- generate_table_source(bundle, "t_demog", include_duplicate_check = FALSE,
                                        output_mode = "report")
  qc <- generate_table_source(bundle, "t_demog", include_duplicate_check = FALSE,
                              output_mode = "compare")
  qc_checked <- generate_table_source(bundle, "t_demog", include_duplicate_check = TRUE,
                                      output_mode = "compare")
  testthat::expect_true(report$passed)
  testthat::expect_true(no_duplicates$passed)
  testthat::expect_true(qc$passed)
  testthat::expect_true(qc_checked$passed)
  testthat::expect_match(report$source, "WARNING: [USER] duplicate_key", fixed = TRUE)
  testthat::expect_false(grepl("WARNING: [USER] duplicate_key", no_duplicates$source, fixed = TRUE))
  testthat::expect_match(report$source, "proc report data=WORK._TFL_ASM_001", fixed = TRUE)
  testthat::expect_false(grepl("proc compare", report$source, ignore.case = TRUE))
  testthat::expect_match(qc$source, "proc compare base=tables.t_demog compare=WORK._TFL_ASM_001 listvar;", fixed = TRUE)
  testthat::expect_false(grepl("ods rtf file=", qc$source, fixed = TRUE))
  testthat::expect_match(qc_checked$source, "WARNING: [USER] duplicate_key", fixed = TRUE)
  testthat::expect_match(qc_checked$source, "proc compare base=tables.t_demog", fixed = TRUE)
  testthat::expect_false(grepl("ods rtf file=", qc_checked$source, fixed = TRUE))
})

testthat::test_that("large key maps use INPUT DATALINES rather than assignments", {
  bundle <- report_fixture()
  bundle$templates[[1L]]$body$chunks <- rep(bundle$templates[[1L]]$body$chunks, 4L)
  for (index in seq_along(bundle$templates[[1L]]$body$chunks)) {
    bundle$templates[[1L]]$body$chunks[[index]]$id <- paste0("chunk_", index)
  }
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "infile datalines dlm='|' dsd truncover", fixed = TRUE)
  testthat::expect_match(result$source, "input\n    chunk_order :best32.", fixed = TRUE)
  testthat::expect_match(result$source, "datalines;", fixed = TRUE)
  testthat::expect_false(grepl("chunk_order = 1;\n  chunk_id =", result$source, fixed = TRUE))
})

testthat::test_that("one header DATA step independently emits overlapping columns in display order", {
  bundle <- report_fixture()
  columns <- bundle$headers[[1L]]$columns
  columns[[2L]]$id <- "overall_population_with_a_long_id"
  bundle$headers[[1L]]$columns <- columns
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1L]]
  start <- which(lines == "data _TFL_MEM_001;")
  testthat::expect_length(start, 1L)
  membership <- lines[seq.int(start, start + match("run;", lines[start:length(lines)]) - 1L)]
  testthat::expect_equal(sum(membership == "  set _TFL_POP_001;"), 1L)
  testthat::expect_equal(sum(grepl("; output; end;$", membership)), 2L)
  testthat::expect_identical(
    membership[grepl("^  if ", membership)],
    c("  if (TRT01AN = 1) then do; header_column_id = 'a'; column_order = 1; output; end;",
      "  if (1) then do; header_column_id = 'overall_population_with_a_long_id'; column_order = 2; output; end;")
  )
  testthat::expect_false(any(grepl("else", membership, fixed = TRUE)))
  testthat::expect_false(any(grepl("^data _TFL_HCOL_[0-9]+;", lines)))
})

testthat::test_that("QC source preserves custom hooks and is independent of RTF page width", {
  bundle <- report_fixture("portrait")
  bundle$headers[[1L]]$columns[[1L]]$width <- 6.5
  workspace <- new_metadata_workspace(bundle)
  original <- workspace_saved_snapshot(workspace)
  result <- application_generate_source(workspace, "t_demog",
                                        include_duplicate_check = FALSE, output_mode = "compare")
  testthat::expect_true(result$passed)
  if (!isTRUE(result$passed)) return(invisible(NULL))
  source <- result$value
  testthat::expect_true(startsWith(source, bundle$tables[[1L]]$custom_code$before))
  markers <- c("Assemble table rows", bundle$tables[[1L]]$custom_code$after,
               "proc compare base=tables.t_demog compare=WORK._TFL_ASM_001 listvar;")
  positions <- vapply(markers, function(marker) regexpr(marker, source, fixed = TRUE)[[1L]], integer(1L))
  testthat::expect_true(all(positions > 0L) && all(diff(positions) > 0L))
  testthat::expect_false(grepl("ods rtf|proc report|papersize", source, ignore.case = TRUE))
  testthat::expect_identical(workspace_saved_snapshot(workspace), original)
})

testthat::test_that("QC references a dotted table ID as a SAS member name literal", {
  bundle <- report_fixture()
  bundle$tables[[1L]]$id <- "14.1.2"
  result <- generate_table_source(bundle, "14.1.2", output_mode = "compare")
  testthat::expect_true(result$passed)
  testthat::expect_match(result$source, "options validmemname=extend;", fixed = TRUE)
  testthat::expect_match(
    result$source, "proc compare base=tables.'14.1.2'n compare=WORK._TFL_ASM_001 listvar;",
    fixed = TRUE
  )
})

testthat::test_that("key-map DSD records preserve text and use complete SAS character informats", {
  bundle <- report_fixture()
  label <- paste(rep("An investigator's \"A|B\"; &symbol %literal \\line", 20L), collapse = " ")
  bundle$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$label <- label
  bundle$templates[[1L]]$body$chunks[[1L]]$rows[[2L]]$label <- ""
  bundle$templates[[1L]]$body$chunks[[1L]]$rows[[2L]]$cell_format <- "{mean}|{sd}; % &symbol"
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1L]]
  start <- which(lines == "data _TFL_KEY_MAP_001;")
  map <- lines[seq.int(start, start + match("run;", lines[start:length(lines)]) - 1L)]
  testthat::expect_match(paste(map, collapse = "\n"), "label :$&_TFL_LABEL_LEN..", fixed = TRUE)
  testthat::expect_match(paste(map, collapse = "\n"), "cell_format :$&_TFL_CELL_LEN..", fixed = TRUE)
  testthat::expect_true("  datalines4;" %in% map)
  if (!"  datalines4;" %in% map) return(invisible(NULL))
  data_rows <- map[seq.int(match("  datalines4;", map) + 1L, match(";;;;", map) - 1L)]
  testthat::expect_length(data_rows, 3L)
  decoded <- utils::read.table(text = paste(data_rows, collapse = "\n"), sep = "|", quote = "\"",
                              colClasses = "character", na.strings = character(), comment.char = "",
                              stringsAsFactors = FALSE)
  testthat::expect_equal(ncol(decoded), 13L)
  testthat::expect_identical(decoded[[6L]], c(label, "", ""))
  testthat::expect_identical(decoded[[8L]], c("", "mean", "sd"))
  testthat::expect_identical(decoded[[13L]], c("", rep("{mean}|{sd}; % &symbol", 2L)))
  testthat::expect_false(grepl("cardimage", result$source, ignore.case = TRUE))
  testthat::expect_match(paste(map, collapse = "\n"),
                         "infile datalines4 dlm='|' dsd truncover;", fixed = TRUE)
})

testthat::test_that("embedded line breaks do not split key-map input records", {
  bundle <- report_fixture()
  bundle$templates[[1L]]$body$chunks[[1L]]$rows[[1L]]$label <- "A\r\nB"
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  testthat::expect_false(grepl("A\r\nB", result$source, fixed = TRUE))
  testthat::expect_match(result$source, "if _n_ = 1 then label = '410D0A42'x;", fixed = TRUE)
  testthat::expect_length(regmatches(result$source,
                                     gregexpr("label = '410D0A42'x;", result$source, fixed = TRUE))[[1L]], 1L)
})

testthat::test_that("key-map records are independent of header count and expand to the full logical map", {
  map_fields <- c("chunk_order", "chunk_id", "row_order", "row_id", "row_type", "label",
                  "indent_level", "statistic_id", "statistic_order", "digits_mode",
                  "digits_value", "use_header_n", "cell_format")
  original_records <- NULL
  for (column_count in c(1L, 3L, 8L)) {
    bundle <- report_fixture()
    column <- bundle$headers[[1L]]$columns[[1L]]
    column$spanning_header_1 <- NULL
    column$width <- 0.5
    bundle$headers[[1L]]$spanning_headers <- NULL
    bundle$headers[[1L]]$columns <- lapply(seq_len(column_count), function(index) {
      entry <- column
      entry$id <- paste0("header_", index)
      entry$display_order <- index
      entry$condition <- if (index == column_count) "0" else "1"
      entry
    })
    result <- generate_table_source(bundle, "t_demog")
    testthat::expect_true(result$passed)
    lines <- strsplit(result$source, "\n", fixed = TRUE)[[1L]]
    map_start <- which(lines == "data _TFL_KEY_MAP_001;")
    map <- lines[seq.int(map_start, map_start + match("run;", lines[map_start:length(lines)]) - 1L)]
    records <- map[seq.int(match("  datalines;", map) + 1L, match(";", map) - 1L)]
    testthat::expect_length(records, 3L)
    testthat::expect_false(any(grepl("header_column_id|column_order|header_[0-9]", map)))
    testthat::expect_match(result$source, "cross join _TFL_HCOLS_001 as h", fixed = TRUE)
    testthat::expect_match(result$source,
                           "order by m.chunk_order, m.row_order, h.column_order, m.statistic_order;",
                           fixed = TRUE)
    if (is.null(original_records)) original_records <- records
    testthat::expect_identical(records, original_records)

    compact <- utils::read.table(text = paste(records, collapse = "\n"), sep = "|", quote = "\"",
                                colClasses = "character", na.strings = character(),
                                comment.char = "", stringsAsFactors = FALSE)
    testthat::expect_equal(ncol(compact), length(map_fields))
    if (ncol(compact) != length(map_fields)) next
    names(compact) <- map_fields
    headers <- data.frame(header_column_id = paste0("header_", seq_len(column_count)),
                          column_order = as.character(seq_len(column_count)))
    expanded <- merge(compact, headers, by = NULL)
    expanded <- expanded[order(as.integer(expanded$chunk_order), as.integer(expanded$row_order),
                               as.integer(expanded$column_order), as.integer(expanded$statistic_order)), ]
    rownames(expanded) <- NULL
    resolved <- resolve_generation_request(new_generation_request(bundle, "t_demog"))$value
    full_map <- plan_primitive_batches(resolved)$value[[1L]]$result_map
    reference <- do.call(rbind, lapply(full_map, function(entry) {
      as.data.frame(lapply(entry[names(expanded)], as.character), stringsAsFactors = FALSE)
    }))
    testthat::expect_identical(expanded, reference)
  }
})

testthat::test_that("header catalog includes every declared column without consulting membership", {
  bundle <- report_fixture()
  bundle$headers[[1L]]$columns[[2L]]$id <- "empty'column"
  bundle$headers[[1L]]$columns[[2L]]$condition <- "0"
  result <- generate_table_source(bundle, "t_demog")
  testthat::expect_true(result$passed)
  lines <- strsplit(result$source, "\n", fixed = TRUE)[[1L]]
  start <- which(lines == "data _TFL_HCOLS_001;")
  testthat::expect_length(start, 1L)
  catalog <- paste(lines[seq.int(start, start + match("run;", lines[start:length(lines)]) - 1L)],
                   collapse = "\n")
  testthat::expect_match(catalog, "length header_column_id $&_TFL_ID_LEN;", fixed = TRUE)
  testthat::expect_match(catalog, "'a' 'empty''column'", fixed = TRUE)
  testthat::expect_match(catalog, "keep header_column_id column_order;", fixed = TRUE)
  testthat::expect_false(grepl("_TFL_MEM_001", catalog, fixed = TRUE))
})
