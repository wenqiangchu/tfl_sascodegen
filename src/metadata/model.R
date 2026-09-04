# Metadata value model and strict structural decoding helpers.

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
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    add_structure_error(collector, path, field)
    return(NULL)
  }
  if (isTRUE(non_empty) && !nzchar(trimws(value))) {
    add_value_error(collector, path, sprintf("Field '%s' must be non-empty.", field))
    return(NULL)
  }
  value
}

parse_id_value <- function(value, path, collector, field = "id") {
  parsed <- parse_string_value(value, path, collector, field, non_empty = TRUE)
  if (is.null(parsed)) return(NULL)
  parsed
}

parse_integer_value <- function(value, path, collector, field,
                                min_value = -Inf, max_value = Inf) {
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
  if (value <= .Machine$integer.max && value >= -.Machine$integer.max) {
    as.integer(value)
  } else {
    as.numeric(value)
  }
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
      expected_level <- if (identical(field, "spanning_header_1")) 1 else 2
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
  allowed <- c("id", "source_data", "spanning_headers", "columns")
  required <- c("id", "source_data", "columns")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  source_data <- parse_string_value(get_field(value, "source_data"),
                                    error_path_field(path, "source_data"), collector,
                                    "source_data", non_empty = TRUE)
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
  if (is.null(id) || is.null(source_data) || is.null(columns_raw) ||
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
  header <- list(id = id, source_data = source_data, columns = columns)
  if (length(spans) > 0L) {
    check_unique_ids(spans,
                     lapply(seq_along(spans), function(i)
                       error_path_index(error_path_field(path, "spanning_headers"), i - 1L)),
                     collector)
    header <- list(id = id, source_data = source_data,
                   spanning_headers = spans, columns = columns)
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
  fields <- lapply(required, function(field) parse_id_value(
    get_field(value, field), error_path_field(path, field), collector, field
  ))
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
        digits <- raw_digits
      }
    } else {
      digits <- parse_integer_value(raw_digits, error_path_field(path, "digits"),
                                    collector, "digits", min_value = 0)
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
                                        "indent_level", min_value = 0)
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
    condition <- parse_string_value(get_field(value, "condition"),
                                    error_path_field(path, "condition"), collector,
                                    "condition", non_empty = TRUE)
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

parse_primitive_denominator <- function(value, path, collector) {
  allowed <- c("type", "variable", "expression")
  if (!check_mapping(value, path, collector, allowed, "type")) return(NULL)
  denominator_type <- parse_string_value(get_field(value, "type"),
                                         error_path_field(path, "type"), collector, "type")
  if (!is.null(denominator_type) &&
      !denominator_type %in% c("header_population", "non_missing", "custom")) {
    add_value_error(collector, error_path_field(path, "type"),
                    sprintf("Denominator type '%s' is not supported.", denominator_type))
    denominator_type <- NULL
  }
  variable <- NULL
  expression <- NULL
  if (identical(denominator_type, "non_missing")) {
    variable <- parse_string_value(get_field(value, "variable"),
                                   error_path_field(path, "variable"), collector,
                                   "variable", non_empty = TRUE)
    if (has_field(value, "expression")) {
      add_error(collector, "import", "bundle_unknown_field",
                "Field 'expression' is not declared for a non_missing denominator.",
                error_path_field(path, "expression"))
    }
  } else if (identical(denominator_type, "custom")) {
    expression <- parse_string_value(get_field(value, "expression"),
                                     error_path_field(path, "expression"), collector,
                                     "expression", non_empty = TRUE)
    if (has_field(value, "variable")) {
      add_error(collector, "import", "bundle_unknown_field",
                "Field 'variable' is not declared for a custom denominator.",
                error_path_field(path, "variable"))
    }
  } else if (identical(denominator_type, "header_population")) {
    for (field in c("variable", "expression")) {
      if (has_field(value, field)) {
        add_error(collector, "import", "bundle_unknown_field",
                  sprintf("Field '%s' is not declared for a header_population denominator.", field),
                  error_path_field(path, field))
      }
    }
  }
  if (is.null(denominator_type) ||
      (identical(denominator_type, "non_missing") && is.null(variable)) ||
      (identical(denominator_type, "custom") && is.null(expression))) return(NULL)
  result <- list(type = denominator_type)
  if (!is.null(variable)) result$variable <- variable
  if (!is.null(expression)) result$expression <- expression
  result
}

parse_source_contract_value <- function(value, path, collector) {
  allowed <- c("grain", "subject_key", "record_key", "duplicate_policy")
  required <- c("grain", "subject_key", "duplicate_policy")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  grain <- parse_string_value(get_field(value, "grain"), error_path_field(path, "grain"),
                              collector, "grain")
  if (!is.null(grain) && !grain %in% c("subject", "record", "observation")) {
    add_value_error(collector, error_path_field(path, "grain"),
                    sprintf("Source grain '%s' is not supported.", grain))
    grain <- NULL
  }
  subject_key <- parse_string_value(get_field(value, "subject_key"),
                                    error_path_field(path, "subject_key"), collector,
                                    "subject_key", non_empty = TRUE)
  duplicate_policy <- parse_string_value(get_field(value, "duplicate_policy"),
                                         error_path_field(path, "duplicate_policy"), collector,
                                         "duplicate_policy")
  if (!is.null(duplicate_policy) && !identical(duplicate_policy, "error")) {
    add_value_error(collector, error_path_field(path, "duplicate_policy"),
                    "Duplicate policy must be 'error'.")
    duplicate_policy <- NULL
  }
  record_key <- NULL
  if (has_field(value, "record_key")) {
    raw_value <- get_field(value, "record_key")
    # R callers may provide a character vector while YAML always decodes a
    # sequence as a list; normalize both representations for the value model.
    if (is.character(raw_value)) raw_value <- as.list(raw_value)
    raw <- parse_sequence_raw(raw_value, error_path_field(path, "record_key"), collector,
                              "record_key", required = TRUE, allow_empty = FALSE)
    if (!is.null(raw)) {
      record_key <- character()
      for (i in seq_along(raw$items)) {
        parsed <- parse_string_value(raw$items[[i]],
                                     error_path_index(error_path_field(path, "record_key"), i - 1L),
                                     collector, "record_key", non_empty = TRUE)
        if (!is.null(parsed)) record_key <- c(record_key, parsed)
      }
      if (anyDuplicated(record_key)) {
        add_value_error(collector, error_path_field(path, "record_key"),
                        "Record key fields must be unique.")
      }
    }
  }
  if (!is.null(grain) && grain %in% c("record", "observation") && is.null(record_key)) {
    add_required_error(collector, path, "record_key")
  }
  if (!is.null(grain) && identical(grain, "subject") && !is.null(record_key)) {
    add_value_error(collector, error_path_field(path, "record_key"),
                    "Record key is not allowed for subject grain.")
  }
  if (is.null(grain) || is.null(subject_key) || is.null(duplicate_policy)) return(NULL)
  result <- list(grain = grain, subject_key = subject_key,
                 duplicate_policy = duplicate_policy)
  if (!is.null(record_key)) result$record_key <- record_key
  # Re-order to the contract's canonical field order.
  ordered <- list(grain = result$grain, subject_key = result$subject_key)
  if (!is.null(result$record_key)) ordered$record_key <- result$record_key
  ordered$duplicate_policy <- result$duplicate_policy
  ordered
}

parse_hierarchical_denominator_value <- function(value, path, collector) {
  allowed <- c("scope", "unit", "variable", "expression")
  required <- c("scope", "unit")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  scope <- parse_string_value(get_field(value, "scope"), error_path_field(path, "scope"),
                              collector, "scope")
  if (!is.null(scope) && !scope %in% c("header_population", "current_group",
                                       "non_missing", "custom")) {
    add_value_error(collector, error_path_field(path, "scope"),
                    sprintf("Denominator scope '%s' is not supported.", scope))
    scope <- NULL
  }
  unit <- parse_string_value(get_field(value, "unit"), error_path_field(path, "unit"),
                             collector, "unit")
  if (!is.null(unit) && !unit %in% registry_allowed_counting_units) {
    add_value_error(collector, error_path_field(path, "unit"),
                    sprintf("Counting unit '%s' is not supported.", unit))
    unit <- NULL
  }
  variable <- NULL
  expression <- NULL
  if (identical(scope, "non_missing")) {
    variable <- parse_string_value(get_field(value, "variable"),
                                   error_path_field(path, "variable"), collector,
                                   "variable", non_empty = TRUE)
    if (has_field(value, "expression")) {
      add_error(collector, "import", "bundle_unknown_field",
                "Field 'expression' is not declared for a non_missing denominator.",
                error_path_field(path, "expression"))
    }
  } else if (identical(scope, "custom")) {
    expression <- parse_string_value(get_field(value, "expression"),
                                     error_path_field(path, "expression"), collector,
                                     "expression", non_empty = TRUE)
    if (has_field(value, "variable")) {
      add_error(collector, "import", "bundle_unknown_field",
                "Field 'variable' is not declared for a custom denominator.",
                error_path_field(path, "variable"))
    }
  } else if (!is.null(scope)) {
    for (field in c("variable", "expression")) {
      if (has_field(value, field)) {
        add_error(collector, "import", "bundle_unknown_field",
                  sprintf("Field '%s' is not declared for this denominator scope.", field),
                  error_path_field(path, field))
      }
    }
  }
  if (is.null(scope) || is.null(unit) ||
      (identical(scope, "non_missing") && is.null(variable)) ||
      (identical(scope, "custom") && is.null(expression))) return(NULL)
  result <- list(scope = scope, unit = unit)
  if (!is.null(variable)) result$variable <- variable
  if (!is.null(expression)) result$expression <- expression
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
    column_order <- vapply(seq_along(column_raw$items), function(i) {
      parse_integer_value(column_raw$items[[i]],
                          error_path_index(error_path_field(path, "column_order"), i - 1L),
                          collector, "column_order", min_value = 0)
    }, numeric(1L))
    # Column positions are an integer sequence in the value model.  The
    # numeric vapply above keeps large-value diagnostics simple; normalise the
    # representable range back to integer for stable round trips.
    if (all(column_order <= .Machine$integer.max)) {
      column_order <- as.integer(column_order)
    }
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
  allowed <- c("id", "variable", "label_variable", "order_variable", "order_direction",
               "result_sort", "node_role", "node_analysis_id", "missing_policy", "missing_label")
  required <- c("id", "variable", "order_variable", "order_direction", "node_role",
                "missing_policy")
  if (!check_mapping(value, path, collector, allowed, required)) return(NULL)
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
  variable <- parse_string_value(get_field(value, "variable"),
                                 error_path_field(path, "variable"), collector,
                                 "variable", non_empty = TRUE)
  label_variable <- NULL
  if (has_field(value, "label_variable")) {
    label_variable <- parse_string_value(get_field(value, "label_variable"),
                                         error_path_field(path, "label_variable"), collector,
                                         "label_variable", non_empty = TRUE)
  }
  order_variable <- parse_string_value(get_field(value, "order_variable"),
                                       error_path_field(path, "order_variable"), collector,
                                       "order_variable", non_empty = TRUE)
  order_direction <- parse_string_value(get_field(value, "order_direction"),
                                        error_path_field(path, "order_direction"), collector,
                                        "order_direction")
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
  if (is.null(id) || is.null(variable) || is.null(order_variable) ||
      is.null(order_direction) || is.null(node_role) || is.null(missing_policy)) return(NULL)
  result <- list(id = id, variable = variable)
  if (!is.null(label_variable)) result$label_variable <- label_variable
  result$order_variable <- order_variable
  result$order_direction <- order_direction
  if (!is.null(result_sort)) result$result_sort <- result_sort
  result$node_role <- node_role
  if (!is.null(node_analysis_id)) result$node_analysis_id <- node_analysis_id
  result$missing_policy <- missing_policy
  if (!is.null(missing_label)) result$missing_label <- missing_label
  result
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
  counting_unit <- parse_string_value(get_field(value, "counting_unit"),
                                      error_path_field(path, "counting_unit"), collector,
                                      "counting_unit")
  if (!is.null(counting_unit) && !counting_unit %in% registry_allowed_counting_units) {
    add_value_error(collector, error_path_field(path, "counting_unit"),
                    sprintf("Counting unit '%s' is not supported.", counting_unit))
    counting_unit <- NULL
  }
  distinct_key <- NULL
  if (has_field(value, "distinct_key")) {
    raw_key_value <- get_field(value, "distinct_key")
    if (is.character(raw_key_value)) raw_key_value <- as.list(raw_key_value)
    raw_key <- parse_sequence_raw(raw_key_value,
                                  error_path_field(path, "distinct_key"), collector,
                                  "distinct_key", required = TRUE, allow_empty = FALSE)
    if (!is.null(raw_key)) {
      distinct_key <- character()
      for (i in seq_along(raw_key$items)) {
        parsed <- parse_string_value(raw_key$items[[i]],
                                     error_path_index(error_path_field(path, "distinct_key"), i - 1L),
                                     collector, "distinct_key", non_empty = TRUE)
        if (!is.null(parsed)) distinct_key <- c(distinct_key, parsed)
      }
    }
  }
  if (identical(counting_unit, "distinct_key") && is.null(distinct_key)) {
    add_required_error(collector, path, "distinct_key")
  }
  if (!is.null(counting_unit) && !identical(counting_unit, "distinct_key") &&
      !is.null(distinct_key)) {
    add_value_error(collector, error_path_field(path, "distinct_key"),
                    "Distinct key is only allowed for the distinct_key counting unit.")
  }
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
      denominator <- parse_hierarchical_denominator_value(
        get_field(value, "denominator"), error_path_field(path, "denominator"), collector
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
  for (i in seq_along(chunk$analysis_blocks)) {
    block <- chunk$analysis_blocks[[i]]
    block_path <- error_path_index(error_path_field(path, "analysis_blocks"), i - 1L)
    if (!block$anchor_level %in% level_ids) {
      add_value_error(collector, error_path_field(block_path, "anchor_level"),
                      sprintf("Anchor level '%s' is not declared.", block$anchor_level))
    }
  }
  for (i in seq_along(chunk$levels)) {
    level <- chunk$levels[[i]]
    level_path <- error_path_index(error_path_field(path, "levels"), i - 1L)
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
  source_contract <- parse_source_contract_value(
    get_field(value, "source_contract"), error_path_field(path, "source_contract"), collector
  )
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
  if (is.null(source_contract) || is.null(levels_raw) || is.null(blocks_raw) ||
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
  result <- list(source_contract = source_contract, levels = levels,
                 analysis_blocks = blocks)
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
    denominator <- parse_primitive_denominator_value(
      get_field(value, "denominator"), error_path_field(path, "denominator"), collector
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
    if (is.null(id) || is.null(source_data) || is.null(denominator) ||
        is.null(rows_raw) || length(rows) != length(rows_raw$items)) return(NULL)
    result$denominator <- denominator
    result$rows <- rows
  } else if (identical(type, "hierarchical_summary")) {
    hierarchical <- parse_hierarchical_chunk_value(value, path, collector, registry, definition)
    if (is.null(id) || is.null(source_data) || is.null(hierarchical)) return(NULL)
    result$source_contract <- hierarchical$source_contract
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
  id <- parse_id_value(get_field(value, "id"), error_path_field(path, "id"), collector)
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
  if (!is.null(schema_version) && !identical(as.integer(schema_version), 1L)) {
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
    schema_version = 1L,
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
