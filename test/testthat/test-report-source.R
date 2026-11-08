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
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl", counting_unit = "distinct_subject", analysis_variable = "AGE",
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
  # Pagination must run after custom_code.after: the contract is that after edits
  # WORK._TFL_ASM_001 in place, so anything that reads or replaces that dataset
  # has to come later or the edit is silently discarded.
  markers <- c("Project setup before", "Select the table population", "Assemble table rows",
               "Update the fixed report input", "data _TFL_BLOCKS_001;",
               "ods rtf file='t_demog.rtf' style=rtf;",
               "proc report data=WORK._TFL_PAGED_001", "ods rtf close;")
  positions <- vapply(markers, function(marker) regexpr(marker, source, fixed = TRUE)[[1L]], integer(1L))
  testthat::expect_true(all(positions > 0L))
  testthat::expect_true(all(diff(positions) > 0L))
  # ODS RTF CLOSE is the last reporting statement; the footnote reset that
  # follows it is global cleanup, not report output.
  testthat::expect_true(endsWith(source, "ods rtf close;
footnote;"))
  testthat::expect_identical(source, generate_table_source(bundle, "t_demog")$source)
})

# The assembly section ends at WORK._TFL_ASM_001 because that is the dataset the
# custom-code contract exposes. Pagination used to be appended to the assembly
# section, which ran it before custom_code.after and threw the edit away.
testthat::test_that("custom_code.after runs before pagination, not after it", {
  bundle <- report_fixture()
  source <- generate_table_source(bundle, "t_demog")$source
  order <- function(text) regexpr(text, source, fixed = TRUE)[[1L]]
  after_at <- order("Update the fixed report input")
  paginate_at <- order("data _TFL_BLOCKS_001;")
  report_at <- order("proc report data=WORK._TFL_PAGED_001")
  testthat::expect_true(after_at > 0L)
  testthat::expect_true(paginate_at > after_at)
  testthat::expect_true(report_at > paginate_at)

  # The assembly step must hand over the dataset the contract names, and the last
  # thing before custom_code.after must be that hand-over -- no pagination.
  before_after <- substr(source, 1L, after_at)
  testthat::expect_match(before_after, "out=WORK._TFL_ASM_001", fixed = TRUE)
  testthat::expect_false(grepl("_TFL_BLOCKS_001", before_after, fixed = TRUE))
  testthat::expect_false(grepl("_TFL_PAGED_001", before_after, fixed = TRUE))
})

# Compare mode only diffs WORK._TFL_ASM_001 against the saved table, so building
# pages there is dead work that also hides the fact that the QC path never sees
# the paginated dataset.
testthat::test_that("compare mode does not paginate", {
  source <- generate_table_source(report_fixture(), "t_demog", output_mode = "compare")$source
  testthat::expect_false(grepl("_TFL_BLOCKS_001", source, fixed = TRUE))
  testthat::expect_false(grepl("_TFL_PAGED_001", source, fixed = TRUE))
  testthat::expect_false(grepl("page_group", source, fixed = TRUE))
  testthat::expect_match(source, "proc compare", fixed = TRUE)
})

testthat::test_that("Letter layout reserves margins and borders without changing header widths", {
  landscape_bundle <- report_fixture("landscape")
  portrait_bundle <- report_fixture("portrait")
  landscape <- generate_table_source(landscape_bundle, "t_demog")$source
  portrait <- generate_table_source(portrait_bundle, "t_demog")$source
  for (bundle in list(landscape_bundle, portrait_bundle)) {
    layout <- report_page_layout(bundle$headers[[1L]])
    printable <- layout$paper_width - 2 * layout$margin
    grid <- layout$stub_width +
      sum(vapply(bundle$headers[[1L]]$columns, `[[`, numeric(1L), "width"))
    testthat::expect_lte(grid + 2 * layout$border_width_pt / 72, printable)
    # ODS RTF splits a table into horizontally repeated panels, printed on
    # separate pages with the stub only on the first, when the content grid does
    # not fit with slack for padding and borders. A grid that merely equals the
    # printable width is not enough; the reserve is what keeps one panel.
    testthat::expect_gte(printable - grid, layout$fit_reserve)
    testthat::expect_gt(layout$stub_width, 0)
  }
  testthat::expect_match(landscape, "papersize=letter orientation=landscape", fixed = TRUE)
  testthat::expect_match(portrait, "papersize=letter orientation=portrait", fixed = TRUE)
  landscape_layout <- report_page_layout(landscape_bundle$headers[[1L]])
  portrait_layout <- report_page_layout(portrait_bundle$headers[[1L]])
  testthat::expect_match(
    landscape, paste0("cellwidth=", sas_report_number(landscape_layout$stub_width), "in"),
    fixed = TRUE
  )
  testthat::expect_match(
    portrait, paste0("cellwidth=", sas_report_number(portrait_layout$stub_width), "in"),
    fixed = TRUE
  )
  testthat::expect_match(landscape, "borderwidth=0.75pt", fixed = TRUE)
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
  # A blank row marks a block boundary: a new chunk, a top-level node, or the
  # end of a node's below rows. Depth changes alone do not qualify, because
  # indentation already expresses nesting between a node and its children.
  testthat::expect_match(source, "(hierarchy_level = 1 and row_role ne 'static') or", fixed = TRUE)
  testthat::expect_match(source, "chunk_order ne previous_chunk", fixed = TRUE)
})

testthat::test_that("Header source duplicates are warned before population filtering without deduplication", {
  bundle <- report_fixture()
  checked <- generate_table_source(bundle, "t_demog")$source
  unchecked <- generate_table_source(bundle, "t_demog", include_duplicate_check = FALSE)$source
  testthat::expect_match(checked, "WARNING: [USER] header_subject_duplicate", fixed = TRUE)
  subject_key <- subject_key_constant()
  testthat::expect_match(checked, paste0("keep=", subject_key, ");"), fixed = TRUE)
  testthat::expect_match(checked, paste0("by ", subject_key, ";"), fixed = TRUE)
  testthat::expect_match(checked, paste0("not missing(", subject_key, ")"), fixed = TRUE)
  testthat::expect_match(checked, "_tfl_count_text = strip(put(_tfl_header_count, best.));", fixed = TRUE)
  # A PUT statement accepts variables and formats, never expressions: a function call
  # inside PUTLOG is a syntax error, so assert the count is referenced by name.
  putlog_line <- regmatches(
    checked,
    regexpr("putlog 'WARNING: \\[USER\\] header_subject_duplicate[^;]*;", checked)
  )[[1L]]
  testthat::expect_length(putlog_line, 1L)
  testthat::expect_false(grepl("(", putlog_line, fixed = TRUE))
  testthat::expect_match(checked, "proc sort data=_TFL_HSUBJ_001 out=_TFL_HSUBJS_001;", fixed = TRUE)
  testthat::expect_lt(regexpr("output _TFL_HSUBJ_001;", checked, fixed = TRUE)[[1L]],
                      regexpr("if not (SAFFL = 'Y') then delete;", checked, fixed = TRUE)[[1L]])
  testthat::expect_false(grepl("_TFL_HSUBJ", unchecked, fixed = TRUE))
  testthat::expect_false(grepl("header_subject_duplicate", unchecked, fixed = TRUE))
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
  testthat::expect_error(report_page_layout(too_wide$headers[[1L]]),
                         "leave no space for the stub")
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
  testthat::expect_match(report$source, "proc report data=WORK._TFL_PAGED_001", fixed = TRUE)
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

# QC compares WORK._TFL_ASM_001 against a saved baseline with `proc compare ...
# listvar`, so any extra column is reported as a variable difference against every
# baseline produced before it existed. gap_before is internal bookkeeping for the
# blank-row rule and must not survive into that dataset.
testthat::test_that("the assembled dataset carries no internal bookkeeping columns", {
  bundle <- report_fixture()
  source <- generate_table_source(bundle, "t_demog")$source
  assembly <- substr(source, 1L, regexpr("Update the fixed report input", source, fixed = TRUE)[[1L]])
  # The blank-row step is the only place gap_before is computed, and its keep
  # list is what decides whether the column reaches _TFL_ASM_001.
  spacing <- strsplit(assembly, "data _TFL_SPACING_001;", fixed = TRUE)[[1L]][[2L]]
  keep_line <- regmatches(spacing, regexpr("keep [^;]*;", spacing))[[1L]]
  testthat::expect_match(keep_line, "report_order", fixed = TRUE)
  testthat::expect_false(grepl("gap_before", keep_line, fixed = TRUE),
                         label = keep_line)
  # The rule still has to work; only the column is dropped from the output.
  testthat::expect_match(spacing, "_tfl_gap = _n_ > 1 and", fixed = TRUE)
})

# The pagination contract itself belongs with the report source, not with the
# dummy study: capacity counting, edge padding, disabling, and the footer.
testthat::test_that("pagination counts printed lines, pads edges, and can be disabled", {
  header <- report_fixture()$headers[[1L]]
  header$page_rows <- 22L
  source <- paste(page_break_source(header), collapse = "
")
  # 22 printed lines, 20 of them body rows: the two edge blanks are mandatory.
  testthat::expect_match(source, "_tfl_block_rows <= 20", fixed = TRUE)
  testthat::expect_match(source, "_tfl_rows_on_page + 1 > 20", fixed = TRUE)
  # The top blank is not doubled when the page already opens with a separator.
  testthat::expect_match(source, "_tfl_needs_top = row_role ne 'spacer'", fixed = TRUE)
  # Every page gets a bottom pad regardless.
  testthat::expect_match(source, "_tfl_edge = 2", fixed = TRUE)

  # 0 means "do not paginate": one page group, pass-through, no block machinery.
  header$page_rows <- 0L
  off <- paste(page_break_source(header), collapse = "
")
  testthat::expect_match(off, "disabled for this header", fixed = TRUE)
  testthat::expect_match(off, "page_group = 1", fixed = TRUE)
  testthat::expect_false(grepl("_TFL_BLOCKS_001", off, fixed = TRUE))

  # A capacity of 3 is the smallest that fits its own two edge blanks.
  header$page_rows <- 3L
  smallest <- paste(page_break_source(header), collapse = "
")
  testthat::expect_match(smallest, "_tfl_block_rows <= 1", fixed = TRUE)
})

testthat::test_that("the footer is right aligned, roman and body sized", {
  source <- paste(rtf_report_source(
    list(header = report_fixture("landscape")$headers[[1L]],
         table = list(id = "t"), template = list(body = list(stub_header = "Stub"))),
    report_page_layout(report_fixture("landscape")$headers[[1L]])
  ), collapse = "
")
  # footnote style=[...] is emitted as literal text and applies nothing, so the
  # overrides have to be inline and j=r is what right-aligns the block.
  testthat::expect_match(source, "footnote1 j=r", fixed = TRUE)
  testthat::expect_match(source, "^S={fontstyle=roman fontweight=light fontsize=10pt}",
                         fixed = TRUE)
  testthat::expect_match(source, "Page ^{thispage} of ^{lastpage}", fixed = TRUE)
  # footnote is global; leaving it set would leak onto the caller's next output.
  testthat::expect_true(endsWith(source, "footnote;"))
})

# Page assignment is a pure function of the printed row roles and the capacity, so
# it is checked against a reference implementation rather than by eyeballing SAS
# output. The reference mirrors the SAS step in page_break_source() exactly,
# including the oversized-block threshold, which is read from the same constant the
# generator uses rather than restated here.
paginate_pages <- function(roles, usable) {
  n <- length(roles)
  block_id <- integer(n)
  id <- 0L
  for (index in seq_len(n)) {
    if (roles[[index]] == "spacer" || index == 1L) id <- id + 1L
    block_id[[index]] <- id
  }
  sizes <- as.integer(table(block_id)[as.character(seq_len(id))])
  page <- integer(n)
  current <- 1L
  rows_on_page <- 0L
  seen <- 0L
  for (index in seq_len(n)) {
    if (block_id[[index]] != seen) {
      seen <- block_id[[index]]
      size <- sizes[[seen]]
      fits <- size <= usable
      if (index == 1L) {
        rows_on_page <- 0L
      } else if (fits && rows_on_page + size > usable) {
        current <- current + 1L
        rows_on_page <- 0L
      } else if (!fits && usable - rows_on_page < oversized_block_min_rows) {
        # An oversized block continues on this page, so leave room for its
        # separator plus at least one content row.
        current <- current + 1L
        rows_on_page <- 0L
      }
    } else if (rows_on_page + 1L > usable) {
      current <- current + 1L
      rows_on_page <- 0L
    }
    page[[index]] <- current
    rows_on_page <- rows_on_page + 1L
  }
  page
}

page_roles_for_blocks <- function(sizes) {
  unlist(lapply(seq_along(sizes), function(index) {
    content <- sizes[[index]] - if (index > 1L) 1L else 0L
    c(if (index > 1L) "spacer", rep("content", max(content, 0L)))
  }))
}

testthat::test_that("page assignment fits every page and never ends one on a separator", {
  usable <- 20L
  cases <- list(
    c(40, 25),   # both blocks oversized: the second must not add an extra row
    c(19, 25),   # a separator must not be stranded as the last row of a page
    c(20, 20),   # exactly full, so the next block starts a new page
    c(21),       # a single oversized block spills onto a second page
    # 17 rows used, 3 free. The second block is oversized, and its separator plus
    # one content row need exactly 2 of those 3 rows, so it belongs on page 1.
    # Requiring 4 free rows (the double-subtraction bug) wrongly moves it.
    c(17, 25),
    # 30 minimal blocks. A block is a separator plus at least one content row, so
    # the smallest real block after the first is 2 printed rows.
    rep(2, 30)
  )
  for (sizes in cases) {
    roles <- page_roles_for_blocks(sizes)
    pages <- paginate_pages(roles, usable)
    sizes_on_page <- as.integer(table(pages))
    label <- paste(sizes, collapse = ",")
    # Capacity is measured in printed body rows, so page_rows - 2 is the limit.
    testthat::expect_lte(max(sizes_on_page), usable, label = label)
    # A separator belongs to the block that follows it, so it can never be the
    # last row of a page: that would print two blank lines at the page edge.
    last_role <- vapply(sort(unique(pages)), function(group) {
      tail(roles[pages == group], 1L)
    }, character(1L))
    testthat::expect_false(any(last_role == "spacer"), label = label)
  }

  # The [17, 25] case pins the threshold: with 3 rows free, the second block must
  # stay on page 1. This is the assertion the double-subtraction bug failed.
  pages <- paginate_pages(page_roles_for_blocks(c(17, 25)), usable)
  testthat::expect_identical(pages[[18L]], 1L)
})

# The reference implementation above is only useful if the generated SAS agrees
# with it, so the two structural rules are also asserted on the emitted source.
testthat::test_that("the page assignment step guards oversized blocks and separators", {
  source <- paste(page_break_source(list(page_rows = 22L)), collapse = "\n")
  # Every non-first row runs the capacity check. A block's first row does not:
  # it is handled by the two guards below, which test the whole block height.
  testthat::expect_match(source, "if _tfl_rows_on_page + 1 > 20 then do;", fixed = TRUE)
  # An oversized block may only continue on the current page if the separator and
  # at least one content row still fit. usable already excludes the two page-edge
  # blanks, so the requirement is exactly oversized_block_min_rows rows free --
  # subtracting them a second time would demand four rows and strand pages short.
  testthat::expect_match(
    source,
    paste0("not _tfl_fits and 20 - _tfl_rows_on_page < ",
           oversized_block_min_rows),
    fixed = TRUE)
  # The comment must state the exception rather than claim blocks never split.
  testthat::expect_false(grepl("never split across pages", source, fixed = TRUE))
  testthat::expect_match(source, "taller than a whole page", fixed = TRUE)
})

# PROC REPORT does not print in physical order: it re-sorts by every ORDER
# variable. The page-edge pads carry no report_order at all, and PROC REPORT runs
# with `missing`, so ordering by report_order puts both pads at the TOP of each
# page -- two blank lines above the body and none below. The report therefore
# needs a key that is complete and unique: a monotonic print order stamped after
# the final sort.
testthat::test_that("the report orders by a complete print key, not by report_order", {
  header <- report_fixture()$headers[[1L]]
  source <- paste(page_break_source(header), collapse = "\n")

  # The print key is stamped after the final sort, so it reflects the sorted
  # sequence including the pads, whose report_order is missing.
  testthat::expect_match(source, "_tfl_print_order = _n_;", fixed = TRUE)
  sort_at <- regexpr("proc sort data=_TFL_PADDED_001 out=", source, fixed = TRUE)[[1L]]
  stamp_at <- regexpr("_tfl_print_order = _n_;", source, fixed = TRUE)[[1L]]
  testthat::expect_gt(sort_at, 0L)
  testthat::expect_gt(stamp_at, sort_at)

  report <- paste(rtf_report_source(
    list(header = header, table = list(id = "t"),
         template = list(body = list(stub_header = "Stub"))),
    report_page_layout(header)
  ), collapse = "\n")
  # report_order is missing on the pads, so it cannot be the report's order key.
  testthat::expect_false(grepl("define report_order", report, fixed = TRUE))
  testthat::expect_match(report, "define _tfl_print_order / order order=internal noprint",
                         fixed = TRUE)
  # The order key has to be listed in COLUMNS to take effect.
  columns_line <- grep("columns page_group", strsplit(report, "
")[[1L]], value = TRUE)
  testthat::expect_length(columns_line, 1L)
  testthat::expect_match(columns_line, "_tfl_print_order", fixed = TRUE)
  testthat::expect_false(grepl("report_order", columns_line, fixed = TRUE))
})

# The internal bookkeeping of the page step must not reach the final dataset: a
# caller column cannot collide with it, and the QC `proc compare` of the assembled
# data must not see it.
testthat::test_that("no _tfl_ bookkeeping survives into the paginated dataset", {
  source <- paste(page_break_source(list(page_rows = 22L)), collapse = "\n")
  used <- unique(regmatches(source, gregexpr("_tfl_[a-z_]+", source))[[1L]])
  internal <- unlist(page_internal_names(), use.names = FALSE)
  # Every derived name is either dropped or is the report's own order key; a name
  # that is neither would leak into the dataset the caller and PROC REPORT see.
  leaked <- setdiff(used, c(internal, "_tfl_print_order"))
  testthat::expect_identical(leaked, character(0L))

  # Each internal name must appear in a drop, and the drops are staged so SAS is
  # never asked to drop a variable an earlier step already removed -- that is a
  # warning, and an unclassified warning fails the dummy study run. A drop is
  # either a DROP statement or a data set (drop=...) option.
  drop_lines <- grep("drop", strsplit(source, "\n")[[1L]], value = TRUE)
  for (group in names(page_internal_names())) {
    names_in_group <- page_internal_names()[[group]]
    testthat::expect_true(
      any(vapply(drop_lines, function(line) {
        all(vapply(names_in_group, function(n) grepl(n, line, fixed = TRUE), logical(1L)))
      }, logical(1L))),
      label = paste("staged drop for", group)
    )
  }
  # The final step keeps the print key and drops only the RETAINed page state.
  final <- grep("^  drop ", strsplit(source, "\n")[[1L]], value = TRUE)
  testthat::expect_true(any(vapply(final, function(line) {
    grepl("_tfl_rows_on_page", line, fixed = TRUE) &&
      !grepl("_tfl_block_start", line, fixed = TRUE)
  }, logical(1L))))
})
