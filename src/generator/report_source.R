# SAS-only report assembly and ODS RTF source. No report is executed in R.

report_column_names <- function(header) {
  sprintf("col_%03d", seq_along(header$columns))
}

report_page_layout <- function(header) {
  paper_width <- if (identical(header$orientation, "landscape")) 11 else 8.5
  # Pin the one-inch RTF margin baseline so width arithmetic and ODS agree.
  margin <- 1
  # ODS RTF splits a table into horizontal panels -- printed on separate pages,
  # with the stub column only on the first panel -- when the content grid does
  # not fit the printable width. Cell padding and borders are not part of the
  # declared cell widths, so the grid needs real slack, not just the border
  # allowance: 1.5pt was measured to be too tight and produced a panel break.
  border_width_pt <- 0.75
  fit_reserve <- 0.25
  stub_width <- paper_width - 2 * margin - fit_reserve -
    2 * border_width_pt / 72 -
    sum(vapply(header$columns, `[[`, numeric(1L), "width"))
  if (!is.finite(stub_width) || stub_width <= 0) {
    stop("Header columns leave no space for the stub within the Letter page margins.", call. = FALSE)
  }
  list(paper_width = paper_width, margin = margin, border_width_pt = border_width_pt,
       fit_reserve = fit_reserve, stub_width = stub_width)
}

sas_report_number <- function(value) {
  format(value, trim = TRUE, scientific = FALSE, digits = 15L)
}

report_text_lengths_source <- function(resolved) {
  collect <- function(value, fields) {
    if (!is.list(value)) return(character())
    result <- character()
    for (index in seq_along(value)) {
      field <- names(value)[index] %||% ""
      if (!is.na(field) && field %in% fields && is.character(value[[index]])) {
        result <- c(result, value[[index]])
      } else if (is.list(value[[index]])) result <- c(result, collect(value[[index]], fields))
    }
    result
  }
  metadata <- list(resolved$template, resolved$header)
  ids <- collect(metadata, "id")
  nested_ids <- unlist(lapply(resolved$template$body$chunks, function(chunk) {
    vapply(chunk$analysis_blocks %||% list(), function(block) paste0(chunk$id, ":", block$id), "")
  }), use.names = FALSE)
  id_length <- max(32L, nchar(c(ids, nested_ids), type = "bytes"))
  label_length <- max(256L, nchar(collect(metadata, c("label", "missing_label")), type = "bytes"))
  formats <- collect(metadata, "cell_format")
  cell_length <- max(256L, vapply(formats, function(format) {
    tokens <- gregexpr("\\{[^{}]+\\}", format, perl = TRUE)[[1L]]
    nchar(format, type = "bytes") + 32L * sum(tokens > 0L)
  }, integer(1L)))
  # A SAS character variable stops at 32767 bytes, and these values become LENGTH
  # statement widths, so an unbounded metadata string would produce a program that
  # only fails inside SAS. The model refuses text above this size, so the clamp
  # guards against a value that slipped past it rather than truncating user input
  # silently.
  sas_character_limit <- 32767L
  id_length <- min(id_length, sas_character_limit)
  label_length <- min(label_length, sas_character_limit)
  cell_length <- min(cell_length, sas_character_limit)
  c(
    "/* Size metadata text explicitly; hierarchical source descriptors extend these bounds. */",
    paste0("%let _TFL_ID_LEN=", id_length, ";"),
    paste0("%let _TFL_LABEL_LEN=", label_length, ";"),
    paste0("%let _TFL_CELL_LEN=", cell_length, ";"),
    "%let _TFL_NODE_LEN=1;",
    paste0("%let _TFL_RUNTIME_LEN=", id_length, ";")
  )
}

header_count_source <- function(header) {
  c(
    "/* Count each header column independently from population membership. */",
    "data _TFL_HCOLS_001;",
    "  length header_column_id $&_TFL_ID_LEN;",
    paste0("  array _tfl_header_ids[", length(header$columns),
           "] $&_TFL_ID_LEN _temporary_ (",
           paste(vapply(header$columns, function(column) sas_character_literal(column$id),
                        character(1L)), collapse = " "), ");"),
    "  do column_order = 1 to dim(_tfl_header_ids);",
    "    header_column_id = _tfl_header_ids[column_order];",
    "    output;",
    "  end;",
    "  keep header_column_id column_order;",
    "run;",
    "proc sql noprint;",
    "  create table _TFL_HN_RAW_001 as",
    "  select column_order, count(distinct USUBJID) as header_n",
    "  from _TFL_MEM_001 group by column_order;",
    "  create table _TFL_HN_001 as",
    "  select c.column_order, coalesce(n.header_n, 0) as header_n",
    "  from _TFL_HCOLS_001 as c left join _TFL_HN_RAW_001 as n",
    "    on c.column_order = n.column_order order by c.column_order;",
    "quit;",
    "data _null_;",
    "  set _TFL_HN_001;",
    "  call symputx(cats('_TFL_N_', put(column_order, z3.)), header_n, 'G');",
    "run;"
  )
}

table_assembly_source <- function(outputs, resolved) {
  columns <- report_column_names(resolved$header)
  column_text <- paste(columns, collapse = " ")
  identities <- paste("chunk_order row_sequence chunk_id row_id runtime_row_id",
                      "row_role hierarchy_level node_key label indent_level")
  c(
    "/* Assemble table rows and cells in template order. */",
    "/* Batch outputs are mapped back through chunk/row/header identities. */",
    "data _TFL_CELLS_001;",
    "  length chunk_id row_id header_column_id $&_TFL_ID_LEN label $&_TFL_LABEL_LEN cell_text $&_TFL_CELL_LEN;",
    "  length runtime_row_id $&_TFL_RUNTIME_LEN node_key $&_TFL_NODE_LEN row_role $16;",
    "  length chunk_order row_sequence column_order indent_level hierarchy_level 8;",
    paste0("  set ", paste(vapply(outputs, `[[`, "", "render_dataset"), collapse = " "), ";"),
    "run;",
    "proc sort data=_TFL_CELLS_001;",
    "  by chunk_order row_sequence column_order;",
    "run;",
    "/* One physical observation supplies every display column of a report row. */",
    "data _TFL_WIDE_001;",
    paste0("  length ", column_text, " $&_TFL_CELL_LEN;"),
    paste0("  retain ", column_text, ";"),
    "  set _TFL_CELLS_001;",
    "  by chunk_order row_sequence;",
    paste0("  if first.row_sequence then call missing(of ", column_text, ");"),
    "  select (column_order);",
    vapply(seq_along(columns), function(index) {
      paste0("    when (", index, ") ", columns[[index]], " = cell_text;")
    }, character(1L)),
    "    otherwise;",
    "  end;",
    "  if last.row_sequence then output;",
    paste0("  keep ", identities, " ", column_text, ";"),
    "run;",
    "/* Insert one blank row at block boundaries. */",
    "/* A block is a node plus the below rows it owns. */",
    "data _TFL_SPACING_001;",
    "  set _TFL_WIDE_001;",
    "  retain previous_chunk previous_role;",
    "  report_order = _n_ * 2;",
    "  /* Three boundaries earn a blank row: a new chunk, a top-level node, and",
    "     the end of a node's below rows. A node whose children are only other",
    "     nodes needs no divider because indentation already expresses the",
    "     nesting; a node that owns below rows does, because those rows share",
    "     the indent of the next sibling. The below-row test looks for a node",
    "     following the run of static rows, not for each static row. Top-level",
    "     excludes static rows, which also carry level 1. */",
    "  _tfl_gap = _n_ > 1 and (chunk_order ne previous_chunk or",
    "    (hierarchy_level = 1 and row_role ne 'static') or",
    "    (previous_role = 'static' and row_role = 'dynamic'));",
    "  previous_chunk = chunk_order; previous_role = row_role;",
    "  output;",
    "  if _tfl_gap then do;",
    "    report_order = report_order - 1;",
    paste0("    call missing(label, of ", column_text, ");"),
    "    indent_level = 0; row_role = 'spacer';",
    "    runtime_row_id = cats('spacer:', put(report_order, best32.));",
    "    output;",
    "  end;",
    # _tfl_gap is internal bookkeeping. QC runs `proc compare ... listvar` against
    # saved baselines, so any column left here is reported as a variable difference
    # on every pre-existing baseline; it is deliberately not kept.
    paste0("  keep report_order ", identities, " ", column_text, ";"),
    "run;",
    "/* Custom code after may update this dataset in place before final output. */",
    "/* Pagination runs later, in the report section, so that an in-place edit of",
    "   this dataset is carried into the pages instead of being overwritten. */",
    "proc sort data=_TFL_SPACING_001 out=WORK._TFL_ASM_001;",
    "  by report_order;",
    "run;"
  )
}

# A block taller than a whole page cannot fit anywhere, so it is the one case
# allowed to split. It may only continue on the current page when the separator
# and at least one content row still fit there: `usable` already excludes the two
# mandatory page-edge blanks, so this is exactly the number of free rows needed,
# with no second subtraction. Sharing the constant with the reference model in the
# tests is what keeps the two implementations from drifting apart.
oversized_block_min_rows <- 2L

# Every name the page step derives for its own bookkeeping, grouped by the point
# that drops it. Listing them in one place is what stops a new helper variable
# from silently reaching the dataset the caller and PROC REPORT see; staging the
# drops is what stops SAS warning that a DROP lists a variable that is already
# gone. _tfl_print_order is deliberately absent: it is the report's order key and
# has to survive.
page_internal_names <- function() {
  list(
    # Consumed once the page assignment is done.
    paged = c("_tfl_block_start", "_tfl_block_id", "_tfl_block_rows"),
    # Consumed by the merge that builds the padded, ordered sequence.
    padded = c("_tfl_edge", "_tfl_needs_top"),
    # RETAINed page state; alive until the print key is stamped.
    final = c("_tfl_rows_on_page", "_tfl_fits")
  )
}

# Rows per page cannot be derived from the metadata: it depends on orientation,
# column widths, font size and cell padding, so the header carries a measured
# number. The count is the total printed body lines, including the mandatory
# blank line at the top and bottom of every page. Zero means "never break a
# page", which keeps the unpaginated behaviour for callers that do not care
# about page layout.
page_break_source <- function(header) {
  page_rows <- header$page_rows %||% default_page_rows
  # Pagination reads the assembled rows after `custom_code.after` has run, and
  # nothing requires that hook to keep physical order consistent with
  # report_order: proc append or an early OUTPUT can insert a row behind rows with
  # a smaller report_order. Blocks are assigned on row sequence, so an unsorted
  # input would give a non-monotonic _tfl_block_id and either a BY failure or rows
  # in the wrong block. Sort once, up front, and let every branch read the copy.
  prepare <- c(
    "/* The after hook may not preserve physical order; blocks are assigned on it. */",
    "proc sort data=WORK._TFL_ASM_001 out=_TFL_PAGEIN_001;",
    "  by report_order;",
    "run;"
  )
  if (is.null(page_rows) || !is.finite(page_rows) || page_rows <= 0L) {
    return(c(prepare,
             "/* Page breaking is disabled for this header. */",
             "data _TFL_PAGED_001;",
             "  set _TFL_PAGEIN_001;",
             "  page_group = 1;",
             "  _tfl_print_order = _n_;",
             "run;"))
  }
  # The model bounds page_rows to the integer range, so this conversion cannot
  # produce NA. An unbounded value here would emit `> NA` in every page guard.
  page_rows <- as.integer(page_rows)
  # Two lines of every page are reserved for the mandatory blank line at the top
  # and bottom, so only the remainder can hold block rows. The model guarantees a
  # non-zero capacity is at least 4, so the remainder is at least 2 and no floor
  # is needed here.
  usable <- page_rows - 2L
  c(
    prepare,
    paste0("/* Group rows into pages of at most ", page_rows, " printed rows. */"),
    paste0("/* ", usable, " of them hold block rows; 2 are the page-edge blanks. */"),
    "/* A block is a chunk or hierarchy-node run. A block that fits is never split;",
    "   a block taller than a whole page cannot fit anywhere, so it is allowed to",
    "   split as the one documented exception. */",
    "/* A page group opens when the next block would overflow the capacity. */",
    "/* Blocks start at a blank row: the spacer is emitted at a block boundary. */",
    "/* Blank rows occupy a printed line, so they count toward the capacity. */",
    # Every derived name carries the _tfl_ prefix and is dropped before the final
    # dataset, so a caller cannot collide with it through a custom column.
    "data _TFL_BLOCKS_001;",
    "  set _TFL_PAGEIN_001;",
    "  _tfl_block_start = row_role = 'spacer' or _n_ = 1;",
    "  retain _tfl_block_id 0;",
    "  if _tfl_block_start then _tfl_block_id + 1;",
    "run;",
    "proc sql noprint;",
    "  create table _TFL_BLOCKSIZE_001 as",
    "  select _tfl_block_id, count(*) as _tfl_block_rows",
    "  from _TFL_BLOCKS_001",
    "  group by _tfl_block_id;",
    "  /* Carry each block's height onto its rows so page assignment is one pass. */",
    "  create table _TFL_BLOCKED_001 as",
    "  select r.*, s._tfl_block_rows",
    "  from _TFL_BLOCKS_001 as r left join _TFL_BLOCKSIZE_001 as s",
    "    on r._tfl_block_id = s._tfl_block_id",
    "  order by r.report_order;",
    "quit;",
    "/* Assign pages row by row. A block that fits is never split: it either",
    "   joins the open page or starts a new one. A block taller than a whole page",
    "   cannot fit anywhere, so it fills the open page and continues on the next.",
    "   Splitting only such blocks keeps every page within the capacity. */",
    "data _TFL_PAGED_001;",
    "  set _TFL_BLOCKED_001;",
    "  by _tfl_block_id;",
    "  retain page_group 1 _tfl_rows_on_page 0 _tfl_fits 0;",
    "  if first._tfl_block_id then do;",
    paste0("    _tfl_fits = _tfl_block_rows <= ", usable, ";"),
    "    if _n_ = 1 then do; page_group = 1; _tfl_rows_on_page = 0; end;",
    paste0("    else if _tfl_fits and _tfl_rows_on_page + _tfl_block_rows > ", usable, " then do;"),
    "      page_group + 1; _tfl_rows_on_page = 0;",
    "    end;",
    paste0("    else if not _tfl_fits and ", usable, " - _tfl_rows_on_page < ",
           oversized_block_min_rows, " then do;"),
    "      /* The block continues on this page, and its first row is a separator.",
    paste0("         Opening it with fewer than ", oversized_block_min_rows,
           " rows left would either"),
    "         overflow the page or strand the separator as the last printed row,",
    "         printing two blanks at the page edge. Keep room for the separator",
    "         plus one content row. */",
    "      page_group + 1; _tfl_rows_on_page = 0;",
    "    end;",
    "  end;",
    "  else do;",
    paste0("    if _tfl_rows_on_page + 1 > ", usable, " then do;"),
    "      page_group + 1; _tfl_rows_on_page = 0;",
    "    end;",
    "  end;",
    "  _tfl_rows_on_page + 1;",
    # Only page_group survives from this step; the block bookkeeping is internal.
    paste0("  drop ", paste(page_internal_names()$paged, collapse = " "), ";"),
    "run;",
    page_padding_source()
  )
}

# Every page opens and closes with exactly one blank line. A page that already
# starts with a block separator has its top blank, so no second one is added;
# the bottom blank is always new because a block separator belongs to the block
# that follows it and therefore never ends a page.
page_padding_source <- function() {
  c(
    "/* Record the first row role of each page group. */",
    "proc sort data=_TFL_PAGED_001 out=_TFL_PAGED_S_001;",
    "  by page_group report_order;",
    "run;",
    "data _TFL_PAGEEDGE_001;",
    "  set _TFL_PAGED_S_001;",
    "  by page_group;",
    "  if first.page_group;",
    "  /* A page already opening with a separator has its top blank line. */",
    "  _tfl_needs_top = row_role ne 'spacer';",
    "  keep page_group _tfl_needs_top;",
    "run;",
    "/* Pad rows reuse the report's own columns, so no identity is listed here.",
    "   The structural copy must come after the driving SET: an obs=0 SET placed",
    "   first reaches end-of-file and ends the step before any row is read.",
    "   Ordering is by _tfl_edge, not by a magic report_order: a top pad sorts",
    "   before any body row, a bottom pad after all of them, and neither depends",
    "   on how large report_order happens to be. */",
    "data _TFL_PADTOP_001;",
    "  if 0 then set _TFL_PAGED_S_001;",
    "  set _TFL_PAGEEDGE_001;",
    "  if _tfl_needs_top;",
    "  row_role = 'spacer'; indent_level = 0; label = '';",
    "run;",
    "data _TFL_PADBOT_001;",
    "  if 0 then set _TFL_PAGED_S_001;",
    "  set _TFL_PAGEEDGE_001;",
    "  row_role = 'spacer'; indent_level = 0; label = '';",
    "run;",
    "/* Tag each row by its edge in one pass. The in= flags are step-local, so",
    "   they neither reach the dataset nor need a separate copy of the body. */",
    "data _TFL_PADDED_001;",
    "  set _TFL_PAGED_S_001(in=_tfl_in_body)",
    "      _TFL_PADTOP_001(in=_tfl_in_top)",
    "      _TFL_PADBOT_001;",
    "  _tfl_edge = ifn(_tfl_in_top, 0, ifn(_tfl_in_body, 1, 2));",
    "run;",
    "proc sort data=_TFL_PADDED_001 out=_TFL_PADDED_S_001",
    "    (drop=_tfl_edge _tfl_needs_top);",
    "  by page_group _tfl_edge report_order;",
    "run;",
    "/* PROC REPORT re-sorts by every ORDER variable rather than printing in",
    "   physical order, and the page-edge pads have no report_order at all. Under",
    "   `missing` those missings sort first, which would put both pads above the",
    "   body of every page. Stamp the already-sorted sequence as a complete,",
    "   unique print key and order the report by that instead.",
    "   The step also drops the page bookkeeping, which is internal to this chain:",
    "   only page_group and the print key leave it. */",
    "data WORK._TFL_PAGED_001;",
    "  set _TFL_PADDED_S_001;",
    "  _tfl_print_order = _n_;",
    paste0("  drop ", paste(page_internal_names()$final, collapse = " "), ";"),
    "run;"
  )
}

report_header_columns <- function(header) {
  names <- report_column_names(header)
  spans <- header$spanning_headers %||% list()
  render_range <- function(positions, level) {
    if (level > 2L) {
      return(paste(vapply(positions, function(position) {
        paste0("(", sas_character_literal(header$columns[[position]]$label), " ",
               names[[position]], ")")
      }, character(1L)), collapse = " "))
    }
    keys <- vapply(positions, function(position) {
      header$columns[[position]][[paste0("spanning_header_", level)]] %||% ""
    }, character(1L))
    runs <- rle(keys)
    ends <- cumsum(runs$lengths)
    starts <- ends - runs$lengths + 1L
    paste(vapply(seq_along(runs$values), function(index) {
      child <- render_range(positions[seq.int(starts[[index]], ends[[index]])], level + 1L)
      key <- runs$values[[index]]
      if (!nzchar(key)) return(child)
      span <- find_object_by_id(spans, key)
      paste0("(", sas_character_literal(span$label), " ", child, ")")
    }, character(1L)), collapse = " ")
  }
  render_range(seq_along(header$columns), 1L)
}

rtf_report_source <- function(resolved, layout) {
  header <- resolved$header
  columns <- report_column_names(header)
  c(
    # Pagination belongs to the report, not to the assembly. The custom-code
    # contract lets `after` update WORK._TFL_ASM_001 in place, so pagination has
    # to read that dataset after the hook has run. Compare mode therefore never
    # paginates: it diffs WORK._TFL_ASM_001 directly.
    page_break_source(header),
    "/* Write the RTF in the caller's current SAS working directory. */",
    paste0("options papersize=letter orientation=", header$orientation,
           " leftmargin=1in rightmargin=1in nodate nonumber;"),
    "title;",
    "footnote;",
    "ods escapechar='^';",
    paste0("ods rtf file=", sas_character_literal(paste0(resolved$table$id, ".rtf")), " style=rtf;"),
    "/* Page x of Y: ODS resolves the fields when the document is opened. */",
    "/* Right aligned, roman, and the same size as the body cells (fs20 = 10pt).",
    "   footnote style=[...] is emitted as literal text, so the overrides must be",
    "   inline ^S={...}; j=r is what right-aligns the block. */",
    "footnote1 j=r \"^S={fontstyle=roman fontweight=light fontsize=10pt}\"",
    "  \"Page ^{thispage} of ^{lastpage}\";",
    "/* ODS RTF repeats the report column headers across page breaks. */",
    "proc report data=WORK._TFL_PAGED_001 nowd missing",
    paste0("    style(report)=[outputwidth=100% borderwidth=", sas_report_number(layout$border_width_pt), "pt]"),
    "    style(header)=[protectspecialchars=off]",
    "    style(column)=[protectspecialchars=off asis=on];",
    paste0("  columns page_group _tfl_print_order indent_level label ",
           report_header_columns(header), ";"),
    "  define page_group / order noprint;",
    "  /* The pads have no report_order, so the report cannot order by it: it",
    "     would sort both page-edge blanks above the body. _tfl_print_order is the",
    "     sequence produced by the final sort, so it reproduces it exactly. */",
    "  define _tfl_print_order / order order=internal noprint;",
    "  define indent_level / display noprint;",
    paste0("  define label / display ", sas_character_literal(resolved$template$body$stub_header %||% ""),
           " width=40 style(column)=[cellwidth=", sas_report_number(layout$stub_width),
           "in just=left fontweight=medium];"),
    vapply(seq_along(columns), function(index) {
      column <- header$columns[[index]]
      paste0("  define ", columns[[index]], " / display \"(N = &_TFL_N_", sprintf("%03d", index),
             ")\" width=16 style(column)=[cellwidth=", sas_report_number(column$width), "in just=",
             column$alignment, "];")
    }, character(1L)),
    "  compute label;",
    "    call define(_col_, 'style/merge',",
    "      cats('style=[pretext=\"^R/RTF''\\li', strip(put(indent_level * 200, best32.))) || ' ''\"]');",
    "  endcomp;",
    "  /* Start each page group on a fresh page. */",
    "  break after page_group / page;",
    "run;",
    "ods rtf close;",
    # footnote1 is a global statement. Leaving it set would print this table's
    # page footer on whatever the caller writes next.
    "footnote;"
  )
}

compare_source <- function(resolved) {
  table_id <- resolved$table$id
  needs_literal <- !grepl("^[A-Za-z_][A-Za-z0-9_]*$", table_id)
  member <- if (needs_literal) paste0(sas_character_literal(table_id), "n") else table_id
  c(
    "/* QC mode compares the generated table assembly with the source table. */",
    "/* The source-side dataset contract is TABLES.<table_id>. */",
    if (needs_literal) "options validmemname=extend;",
    paste0("proc compare base=tables.", member,
           " compare=WORK._TFL_ASM_001 listvar;"),
    "run;"
  )
}
