# SAS-only report assembly and ODS RTF source. No report is executed in R.

report_column_names <- function(header) {
  sprintf("col_%03d", seq_along(header$columns))
}

report_page_layout <- function(header) {
  paper_width <- if (identical(header$orientation, "landscape")) 11 else 8.5
  # Pin the one-inch RTF margin baseline so width arithmetic and ODS agree.
  margin <- 1
  stub_width <- paper_width - 2 * margin - sum(vapply(header$columns, `[[`, numeric(1L), "width"))
  if (!is.finite(stub_width) || stub_width <= 0) {
    stop("Header columns leave no space for the stub within the Letter page margins.", call. = FALSE)
  }
  list(paper_width = paper_width, margin = margin, stub_width = stub_width)
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
    "/* Insert one blank row at chunk or hierarchy-level boundaries. */",
    "data _TFL_SPACING_001;",
    "  set _TFL_WIDE_001;",
    "  retain previous_chunk previous_level;",
    "  report_order = _n_ * 2;",
    "  gap_before = _n_ > 1 and (chunk_order ne previous_chunk or",
    "    (hierarchy_level > 0 and previous_level > 0 and hierarchy_level ne previous_level));",
    "  previous_chunk = chunk_order; previous_level = hierarchy_level;",
    "  output;",
    "  if gap_before then do;",
    "    report_order = report_order - 1;",
    paste0("    call missing(label, of ", column_text, ");"),
    "    indent_level = 0; row_role = 'spacer';",
    "    runtime_row_id = cats('spacer:', put(report_order, best32.));",
    "    output;",
    "  end;",
    paste0("  keep report_order ", identities, " ", column_text, ";"),
    "run;",
    "/* Custom code after may update this dataset in place before final output. */",
    "proc sort data=_TFL_SPACING_001 out=WORK._TFL_ASM_001;",
    "  by report_order;",
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
    "/* Write the RTF in the caller's current SAS working directory. */",
    paste0("options papersize=letter orientation=", header$orientation,
           " leftmargin=1in rightmargin=1in nodate nonumber;"),
    "title;",
    "footnote;",
    "ods escapechar='^';",
    paste0("ods rtf file=", sas_character_literal(paste0(resolved$table$id, ".rtf")), " style=rtf;"),
    "/* ODS RTF repeats the report column headers across page breaks. */",
    "proc report data=WORK._TFL_ASM_001 nowd missing",
    "    style(report)=[outputwidth=100%]",
    "    style(header)=[protectspecialchars=off]",
    "    style(column)=[protectspecialchars=off asis=on];",
    paste0("  columns report_order indent_level label ", report_header_columns(header), ";"),
    "  define report_order / order order=internal noprint;",
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
    "run;",
    "ods rtf close;"
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
