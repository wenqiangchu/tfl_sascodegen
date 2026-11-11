# Metadata value model and strict structural decoding helpers.

# Printed lines that fit on one page: body lines plus the mandatory blank line at
# the top and bottom of every page.
#
# 22 printed lines means 20 body lines.
#
# What is actually known: with 22, Word rendering of the seven dummy-study tables
# produces exactly as many pages as the pagination step produced page groups (1, 2,
# 1, 17, 64, 5, 6) and no table splits across a page boundary. So 22 does not
# overflow these layouts.
#
# What is NOT known is the headroom. Counting body lines per page cannot measure it:
# the fullest pages hold 22, 21 and 22 printed lines for 14.3.1.2, 14.3.1.4 and
# 14.1.2 precisely because the algorithm stops at 22, so those counts only prove the
# limit is respected. How much more a physical page could hold has never been
# measured, and an earlier comment here claimed a comfortable margin that was never
# established. Whether 22 is the right default is still open (D2 in
# docs/design-decisions.md); this constant is not a validated measurement of the
# largest safe page.
#
# It is a layout property, not a data property, so it changes with orientation,
# column widths, font size and cell padding.
default_page_rows <- 22L

is_mapping_value <- function(value) {
  is.list(value) && (length(value) == 0L ||
    (!is.null(names(value)) && all(!is.na(names(value))) &&
       all(nzchar(names(value)))))
}

is_sequence_value <- function(value) {
  is.list(value) && (length(value) == 0L || is.null(names(value)) ||
    all(!is.na(names(value))) && all(!nzchar(names(value))))
}

has_field <- function(value, field) {
  is.list(value) && !is.null(names(value)) && field %in% names(value)
}

get_field <- function(value, field, default = NULL) {
  if (has_field(value, field)) value[[field]] else default
}

add_structure_error <- function(collector, path, field = NULL) {
  message <- if (is.null(field)) {
    "Value has an unsupported structure."
  } else {
    sprintf("Field '%s' has an unsupported structure.", field)
  }
  add_error(collector, "import", "bundle_structure_invalid", message, path)
}

add_value_error <- function(collector, path, message) {
  add_error(collector, "import", "bundle_value_invalid", message, path)
}

add_required_error <- function(collector, path, field) {
  add_error(
    collector,
    "import",
    "bundle_required_field_missing",
    sprintf("Field '%s' is required.", field),
    error_path_field(path, field)
  )
}

check_mapping <- function(value, path, collector, allowed, required = character()) {
  if (!is_mapping_value(value)) {
    add_structure_error(collector, path)
    return(FALSE)
  }
  field_names <- names(value)
  if (is.null(field_names)) field_names <- character()
  duplicates <- unique(field_names[duplicated(field_names)])
  if (length(duplicates) > 0L) {
    for (field in sort(duplicates)) {
      add_error(
        collector,
        "import",
        "bundle_duplicate_key",
        sprintf("Mapping key '%s' is duplicated.", field),
        error_path_field(path, field)
      )
    }
  }
  for (field in required) {
    if (!has_field(value, field)) add_required_error(collector, path, field)
  }
  unknown <- sort(setdiff(field_names, allowed))
  for (field in unknown) {
    add_error(
      collector,
      "import",
      "bundle_unknown_field",
      sprintf("Field '%s' is not declared.", field),
      error_path_field(path, field)
    )
  }
  TRUE
}

parse_string_value <- function(value, path, collector, field,
                               required = TRUE, non_empty = FALSE) {
  if (!required && is.null(value)) return(NULL)
  if (is.null(value) && isTRUE(required)) {
    # A caller that reaches here with no value is asking for a field the surrounding
    # contract requires, but which check_mapping() could not see because it is not in
    # the mapping's field list (for example the value inside a nested object). Letting
    # this fall through to the type check below reported bundle_structure_invalid, i.e.
    # "the value is malformed", for a value that is simply absent -- a different
    # problem with a different fix.
    add_required_error(collector, path, field)
    return(NULL)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    add_structure_error(collector, path, field)
    return(NULL)
  }
  if (isTRUE(non_empty) && !nzchar(trimws(value))) {
    add_value_error(collector, path, sprintf("Field '%s' must be non-empty.", field))
    return(NULL)
  }
  # A SAS character variable stops at 32767 bytes, and metadata text is emitted as
  # character literals and LENGTH widths. Text beyond that cannot be represented, so
  # it is refused here rather than producing a program that only fails inside SAS.
  if (nchar(value, type = "bytes") > 32767L) {
    add_value_error(collector, path,
                    sprintf(paste0("Field '%s' must not exceed 32767 bytes, the largest ",
                                   "SAS character value."), field))
    return(NULL)
  }
  value
}

parse_id_value <- function(value, path, collector, field = "id") {
  parsed <- parse_string_value(value, path, collector, field, non_empty = TRUE)
  if (is.null(parsed)) return(NULL)
  parsed
}

# A table id becomes "tables/<id>.yaml" in the archive, "<id>.rtf" for the report
# output, and the SAS member "tables.<id>" that compare mode references. A template
# id becomes "templates/<id>.yaml". Anything outside this set of characters exports
# to a name that cannot be read back, and a name longer than 32 bytes exceeds the
# SAS member limit. Only these two fields are constrained: every other id is either
# renumbered by the workspace or used as an in-memory key, so tightening them would
# reject bundles that work today.
parse_file_safe_id_value <- function(value, path, collector, field = "id") {
  parsed <- parse_id_value(value, path, collector, field)
  if (is.null(parsed)) return(NULL)
  if (!grepl("^[A-Za-z0-9_.-]+$", parsed, perl = TRUE)) {
    add_value_error(collector, path,
                    sprintf(paste0("Field '%s' must use only letters, digits, '_', ",
                                   "'.' and '-', because it becomes a file and a SAS ",
                                   "member name."), field))
    return(NULL)
  }
  if (nchar(parsed, type = "bytes") > 32L) {
    add_value_error(collector, path,
                    sprintf("Field '%s' must not exceed 32 bytes, the SAS member name limit.",
                            field))
    return(NULL)
  }
  parsed
}

# Integer metadata values are bounded to the R integer range by default.
#
# Every consumer of these values treats them as R integers: they are written into
# SAS statements, compared against integer sequences, or converted with as.integer()
# in the generator. as.integer() is range-gated, so an out-of-range value silently
# becomes NA there and the failure surfaces far from the field that caused it -- as
# a literal `> NA` in a page guard, or `missing value where TRUE/FALSE needed`
# inside an emitter. Requiring each caller to pass the bound was tried and the same
# defect reappeared three times, so the bound is the default and a caller that wants
# a narrower range passes its own min_value/max_value.
#
# Anything outside the range is a value error, reported against the field.
parse_integer_value <- function(value, path, collector, field,
                                min_value = -.Machine$integer.max,
                                max_value = .Machine$integer.max) {
  # A bound beyond the integer range is a programming error: the result could not be
  # represented, so accepting the argument would only move the failure downstream.
  if (min_value < -.Machine$integer.max || max_value > .Machine$integer.max) {
    stop("parse_integer_value() bounds must lie within the R integer range.",
         call. = FALSE)
  }
  if (is.logical(value) || !is.numeric(value) || length(value) != 1L ||
      is.na(value) || !is.finite(value) || value != floor(value) ||
      value < min_value || value > max_value) {
    add_value_error(
      collector,
      path,
      sprintf("Field '%s' must be a finite integer in the allowed range.", field)
    )
    return(NULL)
  }
  as.integer(value)
}

parse_number_value <- function(value, path, collector, field, positive = FALSE) {
  if (is.logical(value) || !is.numeric(value) || length(value) != 1L ||
      is.na(value) || !is.finite(value) || (isTRUE(positive) && value <= 0)) {
    add_value_error(
      collector,
      path,
      sprintf("Field '%s' must be a finite %s number.",
              field, if (isTRUE(positive)) "positive" else "numeric")
    )
    return(NULL)
  }
  as.numeric(value)
}

parse_sequence_raw <- function(value, path, collector, field,
                               required = TRUE, allow_empty = TRUE) {
  if (!required && is.null(value)) return(list(items = list(), present = FALSE))
  if (is.null(value)) {
    add_required_error(collector, path, field)
    return(NULL)
  }
  if (!is_sequence_value(value)) {
    add_structure_error(collector, path, field)
    return(NULL)
  }
  if (!isTRUE(allow_empty) && length(value) == 0L) {
    add_value_error(collector, path, sprintf("Field '%s' must not be empty.", field))
    return(NULL)
  }
  list(items = unname(value), present = TRUE)
}

parse_collection_raw <- function(value, path, collector, field,
                                 required = TRUE, allow_empty = TRUE) {
  if (!required && is.null(value)) return(list(items = list(), keys = NULL, present = FALSE))
  if (!is.list(value)) {
    add_structure_error(collector, path, field)
    return(NULL)
  }
  if (length(value) == 0L) {
    if (!isTRUE(allow_empty)) {
      add_value_error(collector, path, sprintf("Field '%s' must not be empty.", field))
      return(NULL)
    }
    return(list(items = list(), keys = NULL, present = TRUE))
  }
  field_names <- names(value)
  is_mapping <- !is.null(field_names) && all(nzchar(field_names))
  if (!is_mapping && !is.null(field_names) && any(nzchar(field_names))) {
    add_structure_error(collector, path, field)
    return(NULL)
  }
  if (is_mapping) {
    list(items = unname(value), keys = field_names, present = TRUE)
  } else {
    list(items = unname(value), keys = NULL, present = TRUE)
  }
}

check_unique_ids <- function(objects, paths, collector) {
  ids <- vapply(objects, function(object) {
    if (is.list(object) && is.character(object$id) && length(object$id) == 1L) {
      object$id
    } else {
      NA_character_
    }
  }, character(1L))
  seen <- character()
  for (i in seq_along(ids)) {
    id <- ids[[i]]
    if (is.na(id)) next
    if (id %in% seen) {
      add_error(
        collector,
        "import",
        "bundle_id_invalid",
        sprintf("Identifier '%s' is duplicated.", id),
        error_path_field(paths[[i]], "id")
      )
    } else {
      seen <- c(seen, id)
    }
  }
  invisible(NULL)
}

parse_population_value <- function(value, path, collector) {
  allowed <- c("id", "label", "expression")
  if (!check_mapping(value, path, collector, allowed, allowed)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  label <- parse_string_value(get_field(value, "label"),
                              error_path_field(path, "label"), collector, "label")
  expression <- parse_string_value(
    get_field(value, "expression"),
    error_path_field(path, "expression"),
    collector,
    "expression",
    non_empty = TRUE
  )
  if (is.null(id) || is.null(label) || is.null(expression)) return(NULL)
  list(id = id, label = label, expression = expression)
}

parse_spanning_header_value <- function(value, path, collector) {
  allowed <- c("id", "level", "label")
  if (!check_mapping(value, path, collector, allowed, allowed)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  level <- parse_integer_value(get_field(value, "level"),
                               error_path_field(path, "level"), collector, "level",
                               min_value = 1, max_value = 2)
  label <- parse_string_value(get_field(value, "label"),
                              error_path_field(path, "label"), collector, "label")
  if (is.null(id) || is.null(level) || is.null(label)) return(NULL)
  list(id = id, level = level, label = label)
}

parse_header_column_value <- function(value, path, collector) {
  allowed <- c("id", "label", "condition", "display_order", "width", "alignment",
               "spanning_header_1", "spanning_header_2")
  required <- c("id", "label", "condition", "display_order", "width", "alignment")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  label <- parse_string_value(get_field(value, "label"),
                              error_path_field(path, "label"), collector, "label")
  condition <- parse_string_value(get_field(value, "condition"),
                                  error_path_field(path, "condition"), collector,
                                  "condition", non_empty = TRUE)
  display_order <- parse_integer_value(
    get_field(value, "display_order"), error_path_field(path, "display_order"),
    collector, "display_order", min_value = 1
  )
  width <- parse_number_value(get_field(value, "width"), error_path_field(path, "width"),
                              collector, "width", positive = TRUE)
  alignment <- parse_string_value(get_field(value, "alignment"),
                                  error_path_field(path, "alignment"), collector,
                                  "alignment")
  if (!is.null(alignment) && !alignment %in% c("left", "center", "right")) {
    add_value_error(collector, error_path_field(path, "alignment"),
                    sprintf("Field 'alignment' has unsupported value '%s'.", alignment))
    alignment <- NULL
  }
  references <- list()
  for (field in c("spanning_header_1", "spanning_header_2")) {
    if (has_field(value, field)) {
      references[[field]] <- parse_string_value(
        get_field(value, field), error_path_field(path, field), collector, field,
        non_empty = TRUE
      )
    }
  }
  if (is.null(id) || is.null(label) || is.null(condition) || is.null(display_order) ||
      is.null(width) || is.null(alignment) || any(vapply(references, is.null, logical(1L)))) {
    return(NULL)
  }
  result <- list(id = id, label = label, condition = condition,
                 display_order = display_order, width = width, alignment = alignment)
  for (field in c("spanning_header_1", "spanning_header_2")) {
    if (!is.null(references[[field]])) result[[field]] <- references[[field]]
  }
  result
}

validate_header_spanning <- function(header, path, collector) {
  spans <- header$spanning_headers
  if (is.null(spans) || length(spans) == 0L) {
    for (column in header$columns) {
      for (field in c("spanning_header_1", "spanning_header_2")) {
        if (!is.null(column[[field]])) {
          add_value_error(collector, path,
                          sprintf("Column references spanning header '%s' without declarations.",
                                  column[[field]]))
        }
      }
    }
    return(invisible(NULL))
  }
  span_ids <- vapply(spans, `[[`, character(1L), "id")
  span_levels <- vapply(spans, `[[`, numeric(1L), "level")
  for (column_index in seq_along(header$columns)) {
    column <- header$columns[[column_index]]
    for (field in c("spanning_header_1", "spanning_header_2")) {
      reference <- column[[field]]
      if (is.null(reference)) next
      span_index <- match(reference, span_ids)
      field_path <- error_path_field(
        error_path_index(error_path_field(path, "columns"), column_index - 1L), field
      )
      if (is.na(span_index)) {
        add_value_error(collector, field_path,
                        sprintf("Spanning header '%s' is not declared.", reference))
        next
      }
      expected_level <- if (identical(field, "spanning_header_1")) 1L else 2L
      if (!identical(as.integer(span_levels[[span_index]]), expected_level)) {
        add_value_error(collector, field_path,
                        sprintf("Spanning header '%s' has an incompatible level.", reference))
      }
    }
  }
  for (span_id in span_ids) {
    positions <- which(vapply(header$columns, function(column) {
      identical(column$spanning_header_1, span_id) ||
        identical(column$spanning_header_2, span_id)
    }, logical(1L)))
    if (length(positions) > 1L && any(diff(positions) != 1L)) {
      add_value_error(collector, path,
                      sprintf("Columns for spanning header '%s' are not contiguous.", span_id))
    }
  }
  invisible(NULL)
}

parse_header_value <- function(value, path, collector) {
  allowed <- c("id", "source_data", "orientation", "page_rows", "spanning_headers", "columns")
  required <- c("id", "source_data", "orientation", "columns")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  source_data <- parse_string_value(get_field(value, "source_data"),
                                    error_path_field(path, "source_data"), collector,
                                    "source_data", non_empty = TRUE)
  orientation <- parse_string_value(get_field(value, "orientation"),
                                    error_path_field(path, "orientation"), collector,
                                    "orientation")
  if (!is.null(orientation) && !orientation %in% c("portrait", "landscape")) {
    add_value_error(collector, error_path_field(path, "orientation"),
                    "Header orientation must be 'portrait' or 'landscape'.")
    orientation <- NULL
  }
  # Printed lines that fit on one page are a property of the layout, not of the
  # data: the count depends on orientation, column widths, font size and cell
  # padding. It cannot be derived here, so it is configured and defaulted to a
  # measured value. Zero disables page breaking entirely.
  #
  # Every page also spends two of those lines on its mandatory edge blanks, so the
  # body gets page_rows - 2 rows. A block is a separator plus at least one content
  # row, so the body needs at least 2 rows for pagination to make sense: below
  # that every block after the first is oversized, its separator ends up alone on
  # a page and a blank page is printed. The smallest honourable capacity is
  # therefore 4. 1, 2 and 3 are refused instead of silently inflated; 0 stays
  # valid because it means "do not paginate at all".
  #
  # The upper bound comes from parse_integer_value()'s default: page_break_source()
  # converts the capacity with as.integer(), so an unrepresentable value would
  # become NA and every pagination guard would read `> NA`, silently stopping the
  # report from respecting pages.
  page_rows <- NULL
  if (has_field(value, "page_rows")) {
    page_rows <- parse_integer_value(get_field(value, "page_rows"),
                                     error_path_field(path, "page_rows"), collector,
                                     "page_rows", min_value = 0L)
    if (!is.null(page_rows) && page_rows > 0L && page_rows < 4L) {
      add_value_error(collector, error_path_field(path, "page_rows"),
                      paste0("Field 'page_rows' must be 0 (no pagination) or at ",
                             "least 4. Two of every page's lines are the mandatory ",
                             "top and bottom blanks, and a page needs a second row ",
                             "for a block separator plus its first content row, so ",
                             "a smaller capacity cannot be honoured."))
      page_rows <- NULL
    }
  }
  if (is.null(page_rows)) page_rows <- default_page_rows
  spans_raw <- parse_sequence_raw(
    get_field(value, "spanning_headers"), error_path_field(path, "spanning_headers"),
    collector, "spanning_headers", required = FALSE, allow_empty = TRUE
  )
  columns_raw <- parse_sequence_raw(
    get_field(value, "columns"), error_path_field(path, "columns"),
    collector, "columns", required = TRUE, allow_empty = FALSE
  )
  spans <- list()
  if (!is.null(spans_raw) && isTRUE(spans_raw$present)) {
    for (i in seq_along(spans_raw$items)) {
      parsed <- parse_spanning_header_value(
        spans_raw$items[[i]],
        error_path_index(error_path_field(path, "spanning_headers"), i - 1L),
        collector
      )
      if (!is.null(parsed)) spans[[length(spans) + 1L]] <- parsed
    }
  }
  columns <- list()
  if (!is.null(columns_raw)) {
    for (i in seq_along(columns_raw$items)) {
      parsed <- parse_header_column_value(
        columns_raw$items[[i]],
        error_path_index(error_path_field(path, "columns"), i - 1L),
        collector
      )
      if (!is.null(parsed)) columns[[length(columns) + 1L]] <- parsed
    }
  }
  if (is.null(id) || is.null(source_data) || is.null(orientation) || is.null(columns_raw) ||
      length(columns) != length(columns_raw$items)) return(NULL)
  check_unique_ids(columns,
                   lapply(seq_along(columns), function(i)
                     error_path_index(error_path_field(path, "columns"), i - 1L)),
                   collector)
  orders <- vapply(columns, `[[`, numeric(1L), "display_order")
  expected <- seq_len(length(columns))
  if (!identical(as.integer(orders), as.integer(expected))) {
    add_value_error(collector, error_path_field(path, "columns"),
                    "Column display_order values must be consecutive and match sequence order.")
  }
  header <- list(id = id, source_data = source_data, orientation = orientation,
                 page_rows = page_rows, columns = columns)
  if (length(spans) > 0L) {
    check_unique_ids(spans,
                     lapply(seq_along(spans), function(i)
                       error_path_index(error_path_field(path, "spanning_headers"), i - 1L)),
                     collector)
    header <- list(id = id, source_data = source_data, orientation = orientation,
                   page_rows = page_rows, spanning_headers = spans, columns = columns)
  }
  validate_header_spanning(header, path, collector)
  header
}

parse_custom_code_value <- function(value, path, collector) {
  allowed <- c("before", "after")
  if (!check_mapping(value, path, collector, allowed, character())) return(NULL)
  result <- list()
  for (field in allowed) {
    if (!has_field(value, field)) next
    parsed <- parse_string_value(get_field(value, field), error_path_field(path, field),
                                 collector, field)
    if (!is.null(parsed) && nzchar(trimws(parsed))) result[[field]] <- parsed
  }
  result
}

parse_table_value <- function(value, path, collector) {
  allowed <- c("id", "population_id", "header_id", "template_id", "custom_code")
  required <- c("id", "population_id", "header_id", "template_id")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  fields <- lapply(required, function(field) {
    parser <- if (identical(field, "id")) parse_file_safe_id_value else parse_id_value
    parser(get_field(value, field), error_path_field(path, field), collector, field)
  })
  names(fields) <- required
  custom_code <- NULL
  if (has_field(value, "custom_code")) {
    custom_code <- parse_custom_code_value(get_field(value, "custom_code"),
                                           error_path_field(path, "custom_code"), collector)
  }
  if (any(vapply(fields, is.null, logical(1L)))) return(NULL)
  result <- fields
  if (!is.null(custom_code) && length(custom_code) > 0L) result$custom_code <- custom_code
  result
}

parse_statistic_value <- function(value, path, collector, allowed_ids, mode) {
  allowed <- c("id", "digits")
  if (!check_mapping(value, path, collector, allowed, "id")) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  if (!is.null(id) && !id %in% allowed_ids) {
    add_value_error(collector, error_path_field(path, "id"),
                    sprintf("Statistic '%s' is not supported for this chunk type.", id))
    id <- NULL
  }
  has_digits <- has_field(value, "digits")
  digits <- NULL
  if (has_digits) {
    raw_digits <- get_field(value, "digits")
    if (is.character(raw_digits) && length(raw_digits) == 1L &&
        grepl("^[+-][0-9]+$", raw_digits)) {
      if (!identical(mode, "continuous")) {
        add_value_error(collector, error_path_field(path, "digits"),
                        "Relative digits are not supported for this statistic.")
      } else {
        # Only the offset is bounded here. The resolved count is
        # coalesce(base_digits, 0) + digits_value, and base_digits is derived from
        # the data at run time, so statistic_digits_source() guards the result
        # inside the program.
        offset <- suppressWarnings(as.numeric(sub("^[+-]", "", raw_digits)))
        if (!is.finite(offset) || offset > 31) {
          add_value_error(collector, error_path_field(path, "digits"),
                          "A relative digits offset must be between -31 and +31.")
        } else {
          digits <- raw_digits
        }
      }
    } else {
      # SAS bounds the decimal count of w.d to 0-31, and result_render.R emits
      # PUTN(rounded_value, cats('F', 32, '.', resolved_digits)), so 31 is also the
      # largest value that fits inside the fixed width of 32.
      digits <- parse_integer_value(raw_digits, error_path_field(path, "digits"),
                                    collector, "digits", min_value = 0,
                                    max_value = 31L)
    }
  }
  if (!is.null(id) && identical(id, "n") && has_digits) {
    add_value_error(collector, error_path_field(path, "digits"),
                    "Statistic 'n' must not declare digits.")
  }
  if (!is.null(id) && !identical(id, "n") && !has_digits) {
    add_required_error(collector, path, "digits")
  }
  if (is.null(id)) return(NULL)
  result <- list(id = id)
  if (!is.null(digits)) result$digits <- digits
  result
}

extract_placeholders <- function(text) {
  matches <- gregexpr("\\{[A-Za-z][A-Za-z0-9_]*\\}", text, perl = TRUE)[[1L]]
  if (identical(matches, -1L)) return(character())
  tokens <- regmatches(text, list(matches))[[1L]]
  sub("^\\{(.*)\\}$", "\\1", tokens)
}

parse_row_value <- function(value, path, collector, definition) {
  row_contract <- definition$row_contract
  common_fields <- c("id", "type", "label", "indent_level")
  if (!check_mapping(value, path, collector,
                     c(common_fields, "condition", "statistics", "cell_format"),
                     c("id", "type", "label"))) {
    return(NULL)
  }
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  row_type <- parse_string_value(get_field(value, "type"), error_path_field(path, "type"),
                                 collector, "type")
  if (!is.null(row_type) && !row_type %in% row_contract$types) {
    add_value_error(collector, error_path_field(path, "type"),
                    sprintf("Row type '%s' is not supported.", row_type))
    row_type <- NULL
  }
  label <- parse_string_value(get_field(value, "label"), error_path_field(path, "label"),
                              collector, "label")
  indent_level <- NULL
  if (has_field(value, "indent_level")) {
    indent_level <- parse_integer_value(get_field(value, "indent_level"),
                                        error_path_field(path, "indent_level"), collector,
                                        "indent_level", min_value = 0, max_value = 9L)
  }
  if (is.null(id) || is.null(row_type) || is.null(label)) return(NULL)
  result <- list(id = id, type = row_type, label = label)
  if (!is.null(indent_level)) result$indent_level <- indent_level
  if (identical(row_type, "label")) {
    unknown_analysis_fields <- sort(setdiff(names(value), common_fields))
    for (field in unknown_analysis_fields) {
      add_error(collector, "import", "bundle_unknown_field",
                sprintf("Field '%s' is not declared for a label row.", field),
                error_path_field(path, field))
    }
    return(result)
  }

  analysis_allowed <- c(common_fields, "statistics", "cell_format")
  if (isTRUE(row_contract$allow_condition)) analysis_allowed <- c(analysis_allowed, "condition")
  for (field in sort(setdiff(names(value), analysis_allowed))) {
    add_error(collector, "import", "bundle_unknown_field",
              sprintf("Field '%s' is not declared for this analysis row.", field),
              error_path_field(path, field))
  }
  if (isTRUE(row_contract$allow_condition)) {
    # Optional SAS expression, preserved verbatim. Only whitespace means "not provided",
    # matching chunk$filter and denominator.expression.
    condition <- parse_string_value(get_field(value, "condition"),
                                    error_path_field(path, "condition"), collector,
                                    "condition")
    if (!is.null(condition) && !nzchar(trimws(condition))) condition <- NULL
    if (is.null(condition)) return(NULL)
    result$condition <- condition
  }
  statistics_raw <- parse_sequence_raw(get_field(value, "statistics"),
                                       error_path_field(path, "statistics"), collector,
                                       "statistics", required = TRUE, allow_empty = FALSE)
  cell_format <- parse_string_value(get_field(value, "cell_format"),
                                    error_path_field(path, "cell_format"), collector,
                                    "cell_format")
  if (is.null(statistics_raw) || is.null(cell_format)) return(NULL)
  statistics <- list()
  for (i in seq_along(statistics_raw$items)) {
    parsed <- parse_statistic_value(
      statistics_raw$items[[i]],
      error_path_index(error_path_field(path, "statistics"), i - 1L),
      collector,
      row_contract$statistic_ids,
      if (identical(definition$type_id, "continuous_summary")) "continuous" else "categorical"
    )
    if (!is.null(parsed)) statistics[[length(statistics) + 1L]] <- parsed
  }
  if (length(statistics) != length(statistics_raw$items)) return(NULL)
  check_unique_ids(statistics,
                   lapply(seq_along(statistics), function(i)
                     error_path_index(error_path_field(path, "statistics"), i - 1L)),
                   collector)
  placeholders <- sort(unique(extract_placeholders(cell_format)))
  statistic_ids <- sort(unique(vapply(statistics, `[[`, character(1L), "id")))
  if (!identical(placeholders, statistic_ids)) {
    add_value_error(collector, error_path_field(path, "cell_format"),
                    "Cell format placeholders must match statistic IDs.")
  }
  result$statistics <- statistics
  result$cell_format <- cell_format
  result
}

`%||%` <- function(left, right) if (is.null(left)) right else left

parse_denominator_value <- function(value, path, collector,
                                    scopes = c("header_population", "chunk_source")) {
  allowed <- c("scope", "unit", "expression", "distinct_key")
  if (!check_mapping(value, path, collector, allowed, c("scope", "unit"))) return(NULL)
  scope <- parse_string_value(get_field(value, "scope"), error_path_field(path, "scope"),
                              collector, "scope")
  if (!is.null(scope) && !scope %in% scopes) {
    add_value_error(collector, error_path_field(path, "scope"),
                    sprintf("Denominator scope '%s' is not supported for this analysis.", scope))
    scope <- NULL
  }
  unit <- parse_string_value(get_field(value, "unit"), error_path_field(path, "unit"),
                             collector, "unit")
  if (!is.null(unit) && !unit %in% registry_allowed_counting_units) {
    add_value_error(collector, error_path_field(path, "unit"),
                    sprintf("Counting unit '%s' is not supported.", unit))
    unit <- NULL
  }
  expression <- NULL
  if (has_field(value, "expression")) {
    # Optional SAS expression, preserved verbatim and never evaluated by R. Only
    # whitespace is not an expression, so it means "not provided" -- the same rule
    # chunk$filter has always applied. Requiring non-empty here made one optional
    # expression stricter than another for no reason the caller could observe.
    expression <- parse_string_value(get_field(value, "expression"),
                                     error_path_field(path, "expression"), collector,
                                     "expression")
    if (!is.null(expression) && !nzchar(trimws(expression))) expression <- NULL
  }
  distinct_key <- parse_distinct_key_value(value, path, collector, unit)
  validate_counting_unit_pair(collector, path, unit, distinct_key)
  if (identical(scope, "header_population") && !is.null(unit) &&
      !identical(unit, "distinct_subject")) {
    add_value_error(collector, error_path_field(path, "unit"),
                    "Header population denominators require the distinct_subject unit.")
  }
  if (is.null(scope) || is.null(unit)) return(NULL)
  result <- list(scope = scope, unit = unit)
  if (!is.null(expression)) result$expression <- expression
  if (!is.null(distinct_key)) result$distinct_key <- distinct_key
  result
}

parse_result_sort_value <- function(value, path, collector) {
  allowed <- c("metric", "column_order", "direction")
  if (!check_mapping(value, path, collector, allowed, allowed)) return(NULL)
  metric <- get_field(value, "metric")
  if (!check_mapping(metric, error_path_field(path, "metric"), collector,
                     c("analysis_id", "row_id", "statistic_id"),
                     c("analysis_id", "row_id", "statistic_id"))) {
    metric <- NULL
  } else {
    metric <- list(
      analysis_id = parse_id_value(get_field(metric, "analysis_id"),
                                   error_path_field(error_path_field(path, "metric"), "analysis_id"),
                                   collector, "analysis_id"),
      row_id = parse_id_value(get_field(metric, "row_id"),
                              error_path_field(error_path_field(path, "metric"), "row_id"),
                              collector, "row_id"),
      statistic_id = parse_id_value(get_field(metric, "statistic_id"),
                                    error_path_field(error_path_field(path, "metric"), "statistic_id"),
                                    collector, "statistic_id")
    )
    if (any(vapply(metric, is.null, logical(1L)))) metric <- NULL
  }
  column_raw_value <- get_field(value, "column_order")
  if (is.numeric(column_raw_value) || is.integer(column_raw_value)) {
    column_raw_value <- as.list(column_raw_value)
  }
  column_raw <- parse_sequence_raw(column_raw_value,
                                   error_path_field(path, "column_order"), collector,
                                   "column_order", required = TRUE, allow_empty = FALSE)
  column_order <- NULL
  if (!is.null(column_raw)) {
    # Parse element by element. parse_integer_value() records the error and returns
    # NULL, so wrapping it in vapply() aborted the whole call with
    # "values must be length 1, but FUN(X[[1]]) result is length 0" -- an R error
    # that escaped the import boundary instead of becoming an error envelope.
    # distinct_key above parses the same way for the same reason.
    positions <- integer()
    valid <- TRUE
    for (i in seq_along(column_raw$items)) {
      parsed <- parse_integer_value(column_raw$items[[i]],
                                    error_path_index(error_path_field(path, "column_order"),
                                                     i - 1L),
                                    collector, "column_order", min_value = 0)
      if (is.null(parsed)) {
        valid <- FALSE
        next
      }
      positions <- c(positions, parsed)
    }
    # The per-element errors are already recorded, so report nothing further; the
    # NULL result makes the caller drop the whole result_sort.
    if (valid) {
      column_order <- positions
      if (anyDuplicated(column_order)) {
        add_value_error(collector, error_path_field(path, "column_order"),
                        "Column order values must be unique.")
      }
      zero_positions <- which(column_order == 0)
      if (length(zero_positions) > 1L ||
          (length(zero_positions) == 1L && zero_positions != length(column_order))) {
        add_value_error(collector, error_path_field(path, "column_order"),
                        "Column order zero may occur at most once and only at the end.")
      }
    }
  }
  direction <- parse_string_value(get_field(value, "direction"),
                                  error_path_field(path, "direction"), collector, "direction")
  if (!is.null(direction) && !direction %in% c("asc", "desc")) {
    add_value_error(collector, error_path_field(path, "direction"),
                    sprintf("Sort direction '%s' is not supported.", direction))
    direction <- NULL
  }
  if (is.null(metric) || is.null(column_order) || is.null(direction)) return(NULL)
  list(metric = metric, column_order = column_order, direction = direction)
}

parse_level_value <- function(value, path, collector) {
  allowed <- c("id", "parent_level", "variable", "format", "label_variable", "order_variable", "order_direction",
               "result_sort", "node_role", "node_analysis_id", "missing_policy", "missing_label")
  required <- c("id", "variable", "node_role", "missing_policy")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  parent_level <- NULL
  if (has_field(value, "parent_level")) {
    parent_level <- parse_id_value(get_field(value, "parent_level"),
                                   error_path_field(path, "parent_level"), collector,
                                   "parent_level")
  }
  variable <- parse_string_value(get_field(value, "variable"),
                                 error_path_field(path, "variable"), collector,
                                 "variable", non_empty = TRUE)
  format_name <- NULL
  if (has_field(value, "format")) {
    format_name <- parse_string_value(get_field(value, "format"),
                                      error_path_field(path, "format"), collector,
                                      "format", non_empty = TRUE)
    if (!is.null(format_name) && grepl("\\.$", format_name)) {
      add_value_error(collector, error_path_field(path, "format"),
                      "Format must omit the trailing period.")
      format_name <- NULL
    }
  }
  label_variable <- NULL
  if (has_field(value, "label_variable")) {
    label_variable <- parse_string_value(get_field(value, "label_variable"),
                                         error_path_field(path, "label_variable"), collector,
                                         "label_variable", non_empty = TRUE)
  }
  order_variable <- NULL
  if (has_field(value, "order_variable")) {
    order_variable <- parse_string_value(get_field(value, "order_variable"),
                                         error_path_field(path, "order_variable"), collector,
                                         "order_variable", non_empty = TRUE)
  }
  order_direction <- NULL
  if (has_field(value, "order_direction")) {
    order_direction <- parse_string_value(get_field(value, "order_direction"),
                                          error_path_field(path, "order_direction"), collector,
                                          "order_direction")
  }
  # A level is either format-driven or variable-driven, never both. A format
  # supplies the node domain, the display label and the node order together, so
  # label_variable and order_variable would each restate one of those from a
  # source that cannot serve values the data does not contain. Accepting them
  # would silently discard what the caller wrote, so the combination is
  # rejected instead. The same list decides invalid_level below, so it is
  # computed once: a second copy could drift and let an invalid level through.
  format_conflicts <- if (!has_field(value, "format")) character(0L) else {
    candidates <- c("label_variable", "order_variable", "order_direction")
    candidates[vapply(candidates, function(field) has_field(value, field), logical(1L))]
  }
  for (field in format_conflicts) {
    add_value_error(collector, error_path_field(path, field),
                    sprintf(paste0("Field '%s' cannot be combined with 'format'. ",
                                   "A format supplies the node domain, label and ",
                                   "order; declare the level either with ",
                                   "'format' or with 'order_variable' and ",
                                   "'order_direction'."), field))
  }
  if (!has_field(value, "format")) {
    if (!has_field(value, "order_variable")) add_required_error(collector, path, "order_variable")
    if (!has_field(value, "order_direction")) add_required_error(collector, path, "order_direction")
  }
  if (!is.null(order_direction) && !order_direction %in% c("asc", "desc")) {
    add_value_error(collector, error_path_field(path, "order_direction"),
                    sprintf("Order direction '%s' is not supported.", order_direction))
    order_direction <- NULL
  }
  node_role <- parse_string_value(get_field(value, "node_role"),
                                  error_path_field(path, "node_role"), collector, "node_role")
  if (!is.null(node_role) && !node_role %in% c("label", "analysis")) {
    add_value_error(collector, error_path_field(path, "node_role"),
                    sprintf("Node role '%s' is not supported.", node_role))
    node_role <- NULL
  }
  node_analysis_id <- NULL
  if (has_field(value, "node_analysis_id")) {
    node_analysis_id <- parse_id_value(get_field(value, "node_analysis_id"),
                                       error_path_field(path, "node_analysis_id"), collector,
                                       "node_analysis_id")
  }
  if (identical(node_role, "analysis") && is.null(node_analysis_id)) {
    add_required_error(collector, path, "node_analysis_id")
  }
  if (identical(node_role, "label") && !is.null(node_analysis_id)) {
    add_value_error(collector, error_path_field(path, "node_analysis_id"),
                    "Node analysis ID is only allowed for an analysis node.")
  }
  missing_policy <- parse_string_value(get_field(value, "missing_policy"),
                                       error_path_field(path, "missing_policy"), collector,
                                       "missing_policy")
  if (!is.null(missing_policy) && !missing_policy %in% c("exclude", "label", "error")) {
    add_value_error(collector, error_path_field(path, "missing_policy"),
                    sprintf("Missing policy '%s' is not supported.", missing_policy))
    missing_policy <- NULL
  }
  missing_label <- NULL
  if (has_field(value, "missing_label")) {
    missing_label <- parse_string_value(get_field(value, "missing_label"),
                                        error_path_field(path, "missing_label"), collector,
                                        "missing_label")
  }
  if (identical(missing_policy, "label") && is.null(missing_label)) {
    add_required_error(collector, path, "missing_label")
  }
  if (!is.null(missing_policy) && !identical(missing_policy, "label") &&
      !is.null(missing_label)) {
    add_value_error(collector, error_path_field(path, "missing_label"),
                    "Missing label is only allowed with the label missing policy.")
  }
  result_sort <- NULL
  if (has_field(value, "result_sort")) {
    result_sort <- parse_result_sort_value(get_field(value, "result_sort"),
                                           error_path_field(path, "result_sort"), collector)
  }
  invalid_level <- is.null(id) || is.null(variable) || is.null(node_role) ||
    is.null(missing_policy) ||
    (has_field(value, "format") && is.null(format_name)) ||
    length(format_conflicts) > 0L ||
    (!has_field(value, "format") &&
     (is.null(order_variable) || is.null(order_direction)))
  if (invalid_level) return(NULL)
  result <- list(id = id, variable = variable)
  if (!is.null(format_name)) result$format <- format_name
  if (!is.null(parent_level)) result$parent_level <- parent_level
  if (!is.null(label_variable)) result$label_variable <- label_variable
  if (!is.null(order_variable)) result$order_variable <- order_variable
  if (!is.null(order_direction)) result$order_direction <- order_direction
  if (!is.null(result_sort)) result$result_sort <- result_sort
  result$node_role <- node_role
  if (!is.null(node_analysis_id)) result$node_analysis_id <- node_analysis_id
  result$missing_policy <- missing_policy
  if (!is.null(missing_label)) result$missing_label <- missing_label
  result
}

# Counting semantics are shared by hierarchical analysis blocks and primitive
# chunks so both hosts validate the same field pair with identical messages.
parse_counting_unit_value <- function(raw, path, collector) {
  unit <- parse_string_value(raw, path, collector, "counting_unit")
  if (!is.null(unit) && !unit %in% registry_allowed_counting_units) {
    add_value_error(collector, path,
                    sprintf("Counting unit '%s' is not supported.", unit))
    unit <- NULL
  }
  unit
}

parse_distinct_key_value <- function(value, path, collector, counting_unit) {
  if (!has_field(value, "distinct_key")) return(NULL)
  # R callers may pass a character vector while YAML decodes a sequence as a
  # list; normalize both before validating individual entries.
  raw_key_value <- get_field(value, "distinct_key")
  if (is.character(raw_key_value)) raw_key_value <- as.list(raw_key_value)
  raw_key <- parse_sequence_raw(raw_key_value,
                                error_path_field(path, "distinct_key"), collector,
                                "distinct_key", required = TRUE, allow_empty = FALSE)
  if (is.null(raw_key)) return(NULL)
  distinct_key <- character()
  for (i in seq_along(raw_key$items)) {
    parsed <- parse_string_value(raw_key$items[[i]],
                                 error_path_index(error_path_field(path, "distinct_key"), i - 1L),
                                 collector, "distinct_key", non_empty = TRUE)
    if (!is.null(parsed)) distinct_key <- c(distinct_key, parsed)
  }
  if (anyDuplicated(distinct_key)) {
    add_value_error(collector, error_path_field(path, "distinct_key"),
                    "Distinct key fields must be unique.")
    return(NULL)
  }
  distinct_key
}

validate_counting_unit_pair <- function(collector, path, counting_unit, distinct_key) {
  if (identical(counting_unit, "distinct_key") && is.null(distinct_key)) {
    add_required_error(collector, path, "distinct_key")
  }
  if (!is.null(counting_unit) && !identical(counting_unit, "distinct_key") &&
      !is.null(distinct_key)) {
    add_value_error(collector, error_path_field(path, "distinct_key"),
                    "Distinct key is only allowed for the distinct_key counting unit.")
  }
  invisible(NULL)
}

parse_analysis_block_value <- function(value, path, collector, registry) {
  allowed <- c("id", "anchor_level", "placement", "type", "counting_unit", "distinct_key",
               "analysis_variable", "denominator", "rows")
  required <- c("id", "anchor_level", "placement", "type", "counting_unit", "rows")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  anchor_level <- parse_id_value(get_field(value, "anchor_level"),
                                 error_path_field(path, "anchor_level"), collector,
                                 "anchor_level")
  placement <- parse_string_value(get_field(value, "placement"),
                                  error_path_field(path, "placement"), collector, "placement")
  if (!is.null(placement) && !placement %in% c("same_row", "below")) {
    add_value_error(collector, error_path_field(path, "placement"),
                    sprintf("Placement '%s' is not supported.", placement))
    placement <- NULL
  }
  type <- parse_string_value(get_field(value, "type"), error_path_field(path, "type"),
                             collector, "type")
  definition <- NULL
  if (!is.null(type)) {
    definition <- chunk_registry_lookup(registry, type)
    if (is.null(definition) || !identical(definition$capability, "primitive")) {
      add_error(collector, "import", "bundle_chunk_type_unknown",
                sprintf("Chunk type '%s' is not a registered primitive type.", type),
                error_path_field(path, "type"))
      definition <- NULL
    }
  }
  counting_unit <- parse_counting_unit_value(
    get_field(value, "counting_unit"), error_path_field(path, "counting_unit"), collector
  )
  distinct_key <- parse_distinct_key_value(
    value, path, collector, counting_unit
  )
  validate_counting_unit_pair(collector, path, counting_unit, distinct_key)
  analysis_variable <- NULL
  denominator <- NULL
  if (!is.null(definition)) {
    if (identical(type, "continuous_summary")) {
      analysis_variable <- parse_string_value(get_field(value, "analysis_variable"),
                                              error_path_field(path, "analysis_variable"),
                                              collector, "analysis_variable", non_empty = TRUE)
      if (has_field(value, "denominator")) {
        add_error(collector, "import", "bundle_unknown_field",
                  "Field 'denominator' is not declared for a continuous analysis block.",
                  error_path_field(path, "denominator"))
      }
    } else {
      denominator <- parse_denominator_value(
        get_field(value, "denominator"), error_path_field(path, "denominator"), collector,
        scopes = c("header_population", "chunk_source", "current_group")
      )
      if (has_field(value, "analysis_variable")) {
        add_error(collector, "import", "bundle_unknown_field",
                  "Field 'analysis_variable' is not declared for a categorical analysis block.",
                  error_path_field(path, "analysis_variable"))
      }
    }
  }
  rows_raw <- parse_sequence_raw(get_field(value, "rows"), error_path_field(path, "rows"),
                                 collector, "rows", required = TRUE, allow_empty = FALSE)
  rows <- list()
  if (!is.null(rows_raw) && !is.null(definition)) {
    for (i in seq_along(rows_raw$items)) {
      parsed <- parse_row_value(
        rows_raw$items[[i]],
        error_path_index(error_path_field(path, "rows"), i - 1L),
        collector,
        definition
      )
      if (!is.null(parsed)) rows[[length(rows) + 1L]] <- parsed
    }
    if (length(rows) == length(rows_raw$items)) {
      check_unique_ids(rows,
                       lapply(seq_along(rows), function(i)
                         error_path_index(error_path_field(path, "rows"), i - 1L)),
                       collector)
    }
  }
  if (is.null(id) || is.null(anchor_level) || is.null(placement) || is.null(type) ||
      is.null(counting_unit) || is.null(rows_raw) || is.null(definition) ||
      length(rows) != length(rows_raw$items) ||
      (identical(type, "continuous_summary") && is.null(analysis_variable)) ||
      (!identical(type, "continuous_summary") && is.null(denominator))) return(NULL)
  result <- list(id = id, anchor_level = anchor_level, placement = placement,
                 type = type, counting_unit = counting_unit)
  if (!is.null(distinct_key)) result$distinct_key <- distinct_key
  if (!is.null(analysis_variable)) result$analysis_variable <- analysis_variable
  if (!is.null(denominator)) result$denominator <- denominator
  result$rows <- rows
  result
}

validate_hierarchical_references <- function(chunk, path, collector) {
  level_ids <- vapply(chunk$levels, `[[`, character(1L), "id")
  block_ids <- vapply(chunk$analysis_blocks, `[[`, character(1L), "id")
  # A same_row block renders on its anchor level's own node row and only there, and the
  # reference that puts it there is level$node_analysis_id. A block nobody references is
  # still analysed -- its cells are computed and emitted -- but never displayed, so the
  # work is paid for and discarded. Track the referenced ids and report the rest below.
  referenced_block_ids <- character()
  for (level in chunk$levels) {
    if (identical(level$node_role, "analysis") && !is.null(level$node_analysis_id)) {
      referenced_block_ids <- c(referenced_block_ids, level$node_analysis_id)
    }
  }
  for (i in seq_along(chunk$analysis_blocks)) {
    block <- chunk$analysis_blocks[[i]]
    block_path <- error_path_index(error_path_field(path, "analysis_blocks"), i - 1L)
    if (!block$anchor_level %in% level_ids) {
      add_value_error(collector, error_path_field(block_path, "anchor_level"),
                      sprintf("Anchor level '%s' is not declared.", block$anchor_level))
    }
    # A same_row block renders on its anchor level's own node row, so its rows share
    # one order_key: hierarchical.R emits cats(display_order_path, 'A') with no
    # row_order, and the flattening step turns that into a single row_sequence. The
    # wide pivot addresses a cell by (row_sequence, column_order), so a second row
    # would overwrite the first and the extra rows would be dropped silently. A
    # below block carries block_order and row_order in its order_key and is fine.
    if (identical(block$placement, "same_row") && length(block$rows) > 1L) {
      add_value_error(
        collector, error_path_field(block_path, "rows"),
        sprintf(paste0("A same_row block holds exactly one row, but '%s' has %d. ",
                       "Rows in a same_row block share one output row, so only the ",
                       "last would be rendered; use placement 'below' for more."),
                block$id, length(block$rows))
      )
    }
    # The reverse of the node_analysis_id check below: a same_row block must be claimed
    # by the level it is anchored at. A below block is exempt, because it renders as its
    # own static rows under the node rather than on the node row.
    if (identical(block$placement, "same_row") && !block$id %in% referenced_block_ids) {
      add_value_error(
        collector, error_path_field(block_path, "id"),
        sprintf(paste0("same_row block '%s' is not referenced by any level's ",
                       "node_analysis_id, so it would be analysed but never rendered. ",
                       "Reference it from level '%s' or change its placement to 'below'."),
                block$id, block$anchor_level)
      )
    }
  }
  for (i in seq_along(chunk$levels)) {
    level <- chunk$levels[[i]]
    level_path <- error_path_index(error_path_field(path, "levels"), i - 1L)
    if (!is.null(level$parent_level)) {
      if (identical(level$parent_level, level$id) || !level$parent_level %in% level_ids) {
        add_value_error(collector, error_path_field(level_path, "parent_level"),
                        "Parent level must reference another declared level.")
      }
    }
    if (identical(level$node_role, "analysis")) {
      if (!level$node_analysis_id %in% block_ids) {
        add_value_error(collector, error_path_field(level_path, "node_analysis_id"),
                        sprintf("Node analysis '%s' is not declared.", level$node_analysis_id))
      } else {
        block <- chunk$analysis_blocks[[match(level$node_analysis_id, block_ids)]]
        if (!identical(block$anchor_level, level$id) || !identical(block$placement, "same_row")) {
          add_value_error(collector, error_path_field(level_path, "node_analysis_id"),
                          "Node analysis must be a same_row block anchored at the level.")
        }
      }
    }
    if (!is.null(level$result_sort)) {
      metric <- level$result_sort$metric
      if (!metric$analysis_id %in% block_ids) {
        add_value_error(collector,
                        error_path_field(error_path_field(level_path, "result_sort"), "metric"),
                        sprintf("Sort analysis '%s' is not declared.", metric$analysis_id))
      } else {
        block <- chunk$analysis_blocks[[match(metric$analysis_id, block_ids)]]
        # The sort is applied to this level's nodes. If the block is anchored at a
        # different level, its node_key can never match, so the ordering silently falls
        # back to declaration order -- a wrong report rather than an error.
        if (!identical(block$anchor_level, level$id)) {
          add_value_error(collector,
                          error_path_field(error_path_field(level_path, "result_sort"), "metric"),
                          sprintf(paste0("Sort analysis '%s' is anchored at level '%s', ",
                                         "not at the level being sorted ('%s')."),
                                  block$id, block$anchor_level, level$id))
        }
        row_ids <- vapply(block$rows, `[[`, character(1L), "id")
        if (!metric$row_id %in% row_ids) {
          add_value_error(collector,
                          error_path_field(error_path_field(level_path, "result_sort"), "metric"),
                          sprintf("Sort row '%s' is not declared.", metric$row_id))
        } else {
          row <- block$rows[[match(metric$row_id, row_ids)]]
          stat_ids <- if (identical(row$type, "analysis"))
            vapply(row$statistics, `[[`, character(1L), "id") else character()
          if (!metric$statistic_id %in% stat_ids) {
            add_value_error(collector,
                            error_path_field(error_path_field(level_path, "result_sort"), "metric"),
                            sprintf("Sort statistic '%s' is not declared.", metric$statistic_id))
          }
        }
      }
    }
  }
  invisible(NULL)
}

parse_hierarchical_chunk_value <- function(value, path, collector, registry, definition) {
  levels_raw <- parse_sequence_raw(get_field(value, "levels"), error_path_field(path, "levels"),
                                   collector, "levels", required = TRUE, allow_empty = FALSE)
  blocks_raw <- parse_sequence_raw(get_field(value, "analysis_blocks"),
                                   error_path_field(path, "analysis_blocks"), collector,
                                   "analysis_blocks", required = TRUE, allow_empty = FALSE)
  levels <- list()
  if (!is.null(levels_raw)) {
    for (i in seq_along(levels_raw$items)) {
      parsed <- parse_level_value(levels_raw$items[[i]],
                                  error_path_index(error_path_field(path, "levels"), i - 1L),
                                  collector)
      if (!is.null(parsed)) levels[[length(levels) + 1L]] <- parsed
    }
  }
  blocks <- list()
  if (!is.null(blocks_raw)) {
    for (i in seq_along(blocks_raw$items)) {
      parsed <- parse_analysis_block_value(
        blocks_raw$items[[i]],
        error_path_index(error_path_field(path, "analysis_blocks"), i - 1L),
        collector,
        registry
      )
      if (!is.null(parsed)) blocks[[length(blocks) + 1L]] <- parsed
    }
  }
  if (is.null(levels_raw) || is.null(blocks_raw) ||
      length(levels) != length(levels_raw$items) || length(blocks) != length(blocks_raw$items)) {
    return(NULL)
  }
  check_unique_ids(levels,
                   lapply(seq_along(levels), function(i)
                     error_path_index(error_path_field(path, "levels"), i - 1L)),
                   collector)
  check_unique_ids(blocks,
                   lapply(seq_along(blocks), function(i)
                     error_path_index(error_path_field(path, "analysis_blocks"), i - 1L)),
                   collector)
  result <- list(levels = levels, analysis_blocks = blocks)
  validate_hierarchical_references(result, path, collector)
  result
}

parse_chunk_value <- function(value, path, collector, registry) {
  if (!is_mapping_value(value)) {
    add_structure_error(collector, path)
    return(NULL)
  }
  if (!has_field(value, "type")) {
    add_required_error(collector, path, "type")
    return(NULL)
  }
  type <- parse_string_value(get_field(value, "type"), error_path_field(path, "type"),
                             collector, "type")
  if (is.null(type)) return(NULL)
  definition <- chunk_registry_lookup(registry, type)
  if (is.null(definition)) {
    add_error(collector, "import", "bundle_chunk_type_unknown",
              sprintf("Chunk type '%s' is not registered.", type),
              error_path_field(path, "type"))
    return(NULL)
  }
  allowed <- c(definition$required_fields, definition$optional_fields)
  if (!check_mapping(value, path, collector, allowed, definition$required_fields)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  source_data <- parse_string_value(get_field(value, "source_data"),
                                    error_path_field(path, "source_data"), collector,
                                    "source_data", non_empty = TRUE)
  filter <- NULL
  if (has_field(value, "filter")) {
    filter <- parse_string_value(get_field(value, "filter"), error_path_field(path, "filter"),
                                 collector, "filter")
    if (!is.null(filter) && !nzchar(trimws(filter))) filter <- NULL
  }
  result <- list(id = id, type = type, source_data = source_data)
  if (!is.null(filter)) result$filter <- filter

  # Primitive chunks declare their own counting unit; hierarchical chunks
  # declare it per analysis block instead.
  if (identical(definition$capability, "primitive")) {
    counting_unit <- parse_counting_unit_value(
      get_field(value, "counting_unit"), error_path_field(path, "counting_unit"), collector
    )
    distinct_key <- parse_distinct_key_value(value, path, collector, counting_unit)
    validate_counting_unit_pair(collector, path, counting_unit, distinct_key)
    result$counting_unit <- counting_unit
    if (!is.null(distinct_key)) result$distinct_key <- distinct_key
    if (is.null(counting_unit)) return(NULL)
  }

  if (identical(type, "continuous_summary")) {
    analysis_variable <- parse_string_value(
      get_field(value, "analysis_variable"), error_path_field(path, "analysis_variable"),
      collector, "analysis_variable", non_empty = TRUE
    )
    rows_raw <- parse_sequence_raw(get_field(value, "rows"), error_path_field(path, "rows"),
                                   collector, "rows", required = TRUE, allow_empty = FALSE)
    rows <- list()
    if (!is.null(rows_raw)) {
      for (i in seq_along(rows_raw$items)) {
        parsed <- parse_row_value(
          rows_raw$items[[i]], error_path_index(error_path_field(path, "rows"), i - 1L),
          collector, definition
        )
        if (!is.null(parsed)) rows[[length(rows) + 1L]] <- parsed
      }
    }
    if (is.null(id) || is.null(source_data) || is.null(analysis_variable) ||
        is.null(rows_raw) || length(rows) != length(rows_raw$items)) return(NULL)
    result$analysis_variable <- analysis_variable
    result$rows <- rows
  } else if (type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
    # check_mapping() above already reported bundle_required_field_missing when the field
    # is absent. Parsing the NULL anyway produced a second, contradictory
    # bundle_structure_invalid for the same path, so a caller saw "malformed" for a field
    # that was simply not there.
    denominator <- if (has_field(value, "denominator"))
      parse_denominator_value(get_field(value, "denominator"),
                            error_path_field(path, "denominator"), collector) else NULL
    rows_raw <- parse_sequence_raw(get_field(value, "rows"), error_path_field(path, "rows"),
                                   collector, "rows", required = TRUE, allow_empty = FALSE)
    rows <- list()
    if (!is.null(rows_raw)) {
      for (i in seq_along(rows_raw$items)) {
        parsed <- parse_row_value(
          rows_raw$items[[i]], error_path_index(error_path_field(path, "rows"), i - 1L),
          collector, definition
        )
        if (!is.null(parsed)) rows[[length(rows) + 1L]] <- parsed
      }
    }
    if (is.null(id) || is.null(source_data) || is.null(denominator) ||
        is.null(rows_raw) || length(rows) != length(rows_raw$items)) return(NULL)
    result$denominator <- denominator
    result$rows <- rows
  } else if (identical(type, "hierarchical_summary")) {
    hierarchical <- parse_hierarchical_chunk_value(value, path, collector, registry, definition)
    if (is.null(id) || is.null(source_data) || is.null(hierarchical)) return(NULL)
    result$levels <- hierarchical$levels
    result$analysis_blocks <- hierarchical$analysis_blocks
  } else {
    # Registry extensions may be parsed structurally by a future module. The
    # built-in registry deliberately has no opaque fallback for unknown shapes.
    add_error(collector, "import", "bundle_structure_invalid",
              sprintf("Chunk type '%s' has no built-in decoder.", type), path)
    return(NULL)
  }
  result
}

parse_template_value <- function(value, path, collector, registry) {
  allowed <- c("id", "body")
  if (!check_mapping(value, path, collector, allowed, allowed)) return(NULL)
  id <- parse_file_safe_id_value(get_field(value, "id"), error_path_field(path, "id"),
                                collector, "id")
  body <- get_field(value, "body")
  body_path <- error_path_field(path, "body")
  if (!check_mapping(body, body_path, collector, c("stub_header", "chunks"), "chunks")) {
    return(NULL)
  }
  stub_header <- NULL
  if (has_field(body, "stub_header")) {
    stub_header <- parse_string_value(get_field(body, "stub_header"),
                                      error_path_field(body_path, "stub_header"), collector,
                                      "stub_header")
  }
  chunks_raw <- parse_sequence_raw(get_field(body, "chunks"),
                                   error_path_field(body_path, "chunks"), collector,
                                   "chunks", required = TRUE, allow_empty = FALSE)
  chunks <- list()
  if (!is.null(chunks_raw)) {
    for (i in seq_along(chunks_raw$items)) {
      parsed <- parse_chunk_value(
        chunks_raw$items[[i]],
        error_path_index(error_path_field(body_path, "chunks"), i - 1L),
        collector,
        registry
      )
      if (!is.null(parsed)) chunks[[length(chunks) + 1L]] <- parsed
    }
  }
  if (is.null(id) || is.null(chunks_raw) || length(chunks) != length(chunks_raw$items)) return(NULL)
  check_unique_ids(chunks,
                   lapply(seq_along(chunks), function(i)
                     error_path_index(error_path_field(body_path, "chunks"), i - 1L)),
                   collector)
  normalized_body <- list()
  if (!is.null(stub_header)) normalized_body$stub_header <- stub_header
  normalized_body$chunks <- chunks
  list(id = id, body = normalized_body)
}

parse_bundle_value <- function(value, registry = default_chunk_registry()) {
  collector <- new_error_collector()
  root_path <- "$"
  allowed <- c("schema_version", "populations", "headers", "tables", "templates")
  required <- allowed
  if (!check_mapping(value, root_path, collector, allowed, required)) {
    return(list(value = NULL, errors = error_items(collector)))
  }
  schema_version <- parse_integer_value(
    get_field(value, "schema_version"), error_path_field(root_path, "schema_version"),
    collector, "schema_version", min_value = 1
  )
  if (!is.null(schema_version) && !identical(as.integer(schema_version), 2L)) {
    add_error(collector, "import", "bundle_schema_unsupported",
              sprintf("Schema version '%s' is not supported.", schema_version),
              error_path_field(root_path, "schema_version"))
    schema_version <- NULL
  }
  collection_specs <- list(
    populations = list(parser = parse_population_value, allow_empty = TRUE),
    headers = list(parser = parse_header_value, allow_empty = TRUE),
    tables = list(parser = parse_table_value, allow_empty = TRUE),
    templates = list(parser = function(x, p, c) parse_template_value(x, p, c, registry),
                     allow_empty = TRUE)
  )
  parsed_collections <- list()
  for (collection_name in names(collection_specs)) {
    collection_path <- error_path_field(root_path, collection_name)
    raw <- parse_collection_raw(get_field(value, collection_name), collection_path,
                                collector, collection_name, required = TRUE,
                                allow_empty = collection_specs[[collection_name]]$allow_empty)
    objects <- list()
    paths <- list()
    if (!is.null(raw)) {
      for (i in seq_along(raw$items)) {
        item_path <- if (is.null(raw$keys)) {
          error_path_index(collection_path, i - 1L)
        } else {
          error_path_field(collection_path, raw$keys[[i]])
        }
        parsed <- collection_specs[[collection_name]]$parser(
          raw$items[[i]], item_path, collector
        )
        if (!is.null(parsed)) {
          if (!is.null(raw$keys[[i]])) {
            key <- raw$keys[[i]]
            if (!identical(parsed$id, key)) {
              add_error(collector, "import", "bundle_id_invalid",
                        sprintf("Mapping key '%s' does not match object ID.", key),
                        error_path_field(item_path, "id"))
            }
          }
          objects[[length(objects) + 1L]] <- parsed
          paths[[length(paths) + 1L]] <- item_path
        }
      }
      if (length(objects) > 0L) check_unique_ids(objects, paths, collector)
      parsed_collections[[collection_name]] <- objects
    }
  }
  errors <- error_items(collector)
  if (length(errors) > 0L || is.null(schema_version) || length(parsed_collections) != 4L) {
    return(list(value = NULL, errors = errors))
  }
  normalized <- list(
    schema_version = schema_version,
    populations = parsed_collections$populations,
    headers = parsed_collections$headers,
    tables = parsed_collections$tables,
    templates = parsed_collections$templates
  )
  list(value = normalized, errors = list())
}

new_metadata_bundle <- function(
    schema_version = 2L,
    populations = list(),
    headers = list(),
    tables = list(),
    templates = list()) {
  list(
    schema_version = schema_version,
    populations = populations,
    headers = headers,
    tables = tables,
    templates = templates
  )
}
