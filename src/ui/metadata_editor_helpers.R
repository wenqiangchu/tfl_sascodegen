`%||%` <- function(left, right) if (is.null(left)) right else left

editor_error_text <- function(errors) {
  if (!length(errors)) return("Operation failed.")
  paste(vapply(errors, function(x) x$message %||% "Operation failed.", character(1L)), collapse = " ")
}

readonly_editor_input <- function(id, label, value) {
  tags$div(class = "form-group", tags$label(`for` = id, label),
           tags$input(id = id, class = "form-control", value = value %||% "", readonly = "readonly"))
}

new_chunk_seed <- function(type) {
  row <- list(
    id = "row_001", type = "analysis", label = "New row",
    statistics = list(list(id = "n")), cell_format = "{n}"
  )
  if (identical(type, "continuous_summary")) {
    return(list(
      id = "chunk_001", type = type, source_data = "adam.adsl",
      counting_unit = "distinct_subject",
      analysis_variable = "AVAL", rows = list(row)
    ))
  }
  if (type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
    row$statistics <- list(list(id = "n"), list(id = "pct", digits = 1L))
    return(list(
      id = "chunk_001", type = type, source_data = "adam.adsl",
      counting_unit = "distinct_subject",
      denominator = list(scope = "header_population", unit = "distinct_subject"),
      rows = list(row)
    ))
  }
  level <- list(
    id = "level_001", variable = "SOC", order_variable = "SOC",
    order_direction = "asc", node_role = "label", missing_policy = "exclude"
  )
  block <- list(
    id = "analysis_001", anchor_level = level$id, placement = "below",
    type = "continuous_summary", counting_unit = "distinct_subject",
    analysis_variable = "AVAL", rows = list(row)
  )
  list(
    id = "chunk_001", type = "hierarchical_summary", source_data = "adam.adsl",
    levels = list(level), analysis_blocks = list(block)
  )
}

# Row-table collection turns the editable row table back into bundle rows. It lives
# here rather than inside the server closure so the transformation can be tested
# directly: the row table is the only place a label row can be produced, and the
# model rejects analysis-only fields on a label row.
trim_optional <- function(x) {
  x <- as.character(x %||% "")
  if (nzchar(x)) x else NULL
}

normalize_stat_digits <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(NULL)
  if (grepl("^[+-][0-9]+$", x)) x else suppressWarnings(as.integer(x))
}

rows_from_editor_data <- function(cached) {
  lapply(seq_len(nrow(cached)), function(i) {
    z <- as.list(cached[i, , drop = FALSE])
    z$id <- as.character(z$.row_id %||% z$id %||% sprintf("row_%03d", i))
    z$.row_id <- NULL
    z$type <- as.character(z$type)
    z$label <- as.character(z$label)
    z$indent_level <- suppressWarnings(as.integer(z$indent_level))
    if (is.na(z$indent_level)) z$indent_level <- 0L
    z$condition <- trim_optional(z$condition)
    z$cell_format <- as.character(z$cell_format %||% "")
    stat_ids <- strsplit(trimws(as.character(z$statistics %||% "")), "\\s+")[[1L]]
    if (!length(stat_ids) || !nzchar(stat_ids[[1L]])) stat_ids <- character()
    digit_tokens <- strsplit(trimws(as.character(z$digits %||% "")), "\\s+")[[1L]]
    if (!length(digit_tokens) || !nzchar(digit_tokens[[1L]])) digit_tokens <- character()
    z$statistics <- lapply(seq_along(stat_ids), function(j) {
      s <- list(id = stat_ids[[j]])
      # Statistics and Digits are positional, and the Digits cell may list fewer
      # tokens than there are statistics. Index before testing rather than relying
      # on %||%, which is `if (is.null(x)) y else x` and therefore evaluates the
      # out-of-range [[ ]] first.
      d <- if (j <= length(digit_tokens)) digit_tokens[[j]] else "-"
      if (!identical(d, "-") && nzchar(d)) s$digits <- normalize_stat_digits(d)
      s
    })
    z$digits <- NULL
    z$statistics_text <- NULL
    # A label row carries only id, type, label and indent_level; the model rejects
    # everything else on one (model.R common_fields). The row table renders the
    # analysis columns for every row, so the values read from those cells have to be
    # dropped here rather than written through -- otherwise a chunk containing a
    # label row cannot be saved once the row table has been touched.
    if (identical(z$type, "label")) {
      z$statistics <- NULL
      z$cell_format <- NULL
      z$condition <- NULL
    }
    z
  })
}

decorate_template_ui_ids <- function(value) {
  if (is.null(value) || is.null(value$body)) return(value)
  next_id <- 0L
  allocate <- function(prefix) {
    next_id <<- next_id + 1L
    sprintf("%s_%06d", prefix, next_id)
  }
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$ui_uid <- chunk$ui_uid %||% allocate("chunk")
    if (identical(chunk$type, "hierarchical_summary")) {
      for (j in seq_along(chunk$levels %||% list())) {
        chunk$levels[[j]]$ui_uid <- chunk$levels[[j]]$ui_uid %||% allocate("level")
      }
      for (j in seq_along(chunk$analysis_blocks %||% list())) {
        block <- chunk$analysis_blocks[[j]]
        block$ui_uid <- block$ui_uid %||% allocate("analysis")
        chunk$analysis_blocks[[j]] <- block
      }
    }
    value$body$chunks[[i]] <- chunk
  }
  value
}

strip_template_ui_ids <- function(value) {
  if (is.null(value) || is.null(value$body)) return(value)
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$ui_uid <- NULL
    for (j in seq_along(chunk$levels %||% list())) chunk$levels[[j]]$ui_uid <- NULL
    for (j in seq_along(chunk$analysis_blocks %||% list())) chunk$analysis_blocks[[j]]$ui_uid <- NULL
    value$body$chunks[[i]] <- chunk
  }
  value
}

normalize_template_for_compare <- function(value) {
  value <- strip_template_ui_ids(clone_metadata_value(value))
  if (is.null(value) || is.null(value$body)) return(value)
  for (i in seq_along(value$body$chunks %||% list())) {
    chunk <- value$body$chunks[[i]]
    chunk$id <- NULL
    for (j in seq_along(chunk$rows %||% list())) chunk$rows[[j]]$id <- NULL
    level_ids <- vapply(chunk$levels %||% list(), function(x) x$id %||% "", character(1))
    for (j in seq_along(chunk$levels %||% list())) {
      level <- chunk$levels[[j]]; level$id <- NULL
      level$parent_level <- if (!is.null(level$parent_level)) match(level$parent_level, level_ids) else NULL
      chunk$levels[[j]] <- level
    }
    block_ids <- vapply(chunk$analysis_blocks %||% list(), function(x) x$id %||% "", character(1))
    for (j in seq_along(chunk$analysis_blocks %||% list())) {
      block <- chunk$analysis_blocks[[j]]; block$id <- NULL
      block$anchor_level <- if (!is.null(block$anchor_level)) match(block$anchor_level, level_ids) else NULL
      for (k in seq_along(block$rows %||% list())) block$rows[[k]]$id <- NULL
      chunk$analysis_blocks[[j]] <- block
    }
    value$body$chunks[[i]] <- chunk
  }
  value
}

normalize_compare_value <- function(value) {
  if (is.null(value)) return(NULL)
  if (length(value) == 1L && is.character(value) && !nzchar(value)) return(NULL)
  if (is.list(value) && !is.data.frame(value)) {
    out <- lapply(value, normalize_compare_value)
    keep <- !vapply(out, is.null, logical(1))
    out <- out[keep]
    nms <- names(out)
    if (!is.null(nms)) {
      out <- out[nzchar(nms)]
      out <- out[order(names(out))]
    }
    return(out)
  }
  value
}

header_editor_data <- function(header) {
  columns <- header$columns %||% list()
  spans <- header$spanning_headers %||% list()
  labels <- setNames(vapply(spans, function(x) x$label %||% "", character(1)),
                     vapply(spans, function(x) x$id %||% "", character(1)))
  value <- function(column, field) {
    ref <- as.character(column[[field]] %||% "")
    if (startsWith(field, "spanning_header_") && ref %in% names(labels)) labels[[ref]] else ref
  }
  if (!length(columns)) return(data.frame(
    id=character(), label=character(), condition=character(), display_order=integer(),
    width=numeric(), alignment=character(), spanning_header_1=character(),
    spanning_header_2=character(), stringsAsFactors=FALSE))
  fields <- c("id", "label", "condition", "display_order", "width", "alignment",
              "spanning_header_1", "spanning_header_2")
  out <- lapply(fields, function(field) vapply(columns, value, character(1), field=field))
  names(out) <- fields
  out$display_order <- suppressWarnings(as.integer(out$display_order))
  out$width <- suppressWarnings(as.numeric(out$width))
  as.data.frame(out, stringsAsFactors=FALSE)
}

header_from_editor_data <- function(id, source_data, data, orientation,
                                    page_rows = NULL, original = NULL) {
  text <- function(x) if (length(x) != 1L || is.na(x)) "" else as.character(x)
  columns <- lapply(seq_len(nrow(data)), function(i) {
    list(id=trimws(text(data$id[[i]])), label=text(data$label[[i]]),
         condition=text(data$condition[[i]]), display_order=suppressWarnings(as.integer(data$display_order[[i]])),
         width=suppressWarnings(as.numeric(data$width[[i]])), alignment=trimws(text(data$alignment[[i]])))
  })
  spans <- list()
  for (level in 1:2) {
    field <- paste0("spanning_header_", level)
    values <- if (field %in% names(data)) trimws(vapply(data[[field]], text, character(1))) else rep("", nrow(data))
    runs <- rle(values); ends <- cumsum(runs$lengths); starts <- ends-runs$lengths+1L; count <- 0L
    for (run in seq_along(runs$values)) {
      label <- runs$values[[run]]; if (!nzchar(label)) next
      count <- count + 1L; span_id <- sprintf("spanning_header_level%d_%d", level, count)
      spans[[length(spans)+1L]] <- list(id=span_id, level=as.integer(level), label=label)
      for (position in seq.int(starts[[run]], ends[[run]])) columns[[position]][[field]] <- span_id
    }
  }
  result <- list(id=id, source_data=as.character(source_data %||% ""),
                 orientation=as.character(orientation %||% ""))
  # Page capacity is edited, so the posted value wins. A NULL or NA means the
  # control was not rendered yet (it posts NULL before the first update, and NA
  # when the box is empty), so the stored value carries over -- that is what keeps
  # an unrelated edit from resetting it. Blank and unset are the same case on
  # purpose: treating them differently would leave `result` without the field
  # while the baseline has it, and the header would look edited forever.
  capacity <- page_rows
  blank <- is.null(capacity) || (length(capacity) == 1L && is.na(capacity))
  if (blank && !is.null(original)) capacity <- original$page_rows
  if (!is.null(capacity) && length(capacity) == 1L && !is.na(capacity)) {
    # numericInput posts whatever the user typed. Coercing blindly would turn 22.9
    # into 22 and 1e10 into NA with a warning, so the value the model then reports
    # would not be the value the user entered. Pass a non-integer through
    # untouched and let parse_integer_value() reject it by name.
    # 1e10 is integral but outside the integer range, so integrality alone is not
    # enough: as.integer() would produce NA and the model would report a missing
    # value instead of the number the user typed. It is passed through unchanged so
    # the model rejects it by name -- a capacity above the integer range would turn
    # into NA in the generator and disable pagination silently.
    representable <- is.finite(capacity) && capacity == trunc(capacity) &&
      abs(capacity) <= .Machine$integer.max
    result$page_rows <- if (representable) as.integer(capacity) else capacity
  }
  if (length(spans)) result$spanning_headers <- spans
  result$columns <- columns
  if (!is.null(original)) {
    # Compare both sides through the same label-based editor representation.
    # Reconstructed span IDs and field order are not evidence of a user edit.
    #
    # The baseline must not pass `original` back in: that re-enters this branch
    # and recurses without bound. It still has to describe the same shape as
    # `result`, page capacity included, or an untouched header would never compare
    # equal and every open/save would mark it dirty.
    #
    # It carries the *stored* capacity, not the posted one: the baseline answers
    # "what would an unedited header look like", so passing `result$page_rows`
    # would make a capacity change compare equal and silently revert it.
    baseline <- header_from_editor_data(original$id, original$source_data,
                                        header_editor_data(original), original$orientation,
                                        page_rows = original$page_rows)
    if (workspace_canonical_equal(baseline, result)) return(clone_metadata_value(original))
  }
  result
}

editor_collection_name <- function(type) paste0(type, "s")
editor_document <- function(workspace, type, id) {
  collection <- workspace[[editor_collection_name(type)]] %||% list()
  hit <- Filter(function(x) identical(as.character(x$id %||% ""), as.character(id %||% "")), collection)
  if (length(hit) == 1L) clone_metadata_value(hit[[1L]]) else NULL
}
