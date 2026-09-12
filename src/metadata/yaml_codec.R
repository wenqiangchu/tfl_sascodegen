# YAML transport boundary and schema-aware canonical encoder.

coerce_bundle_bytes <- function(input) {
  if (inherits(input, "CanonicalBytes")) return(input$bytes)
  if (is.raw(input)) return(input)
  if (is.character(input) && length(input) == 1L && !is.na(input)) {
    return(charToRaw(enc2utf8(input)))
  }
  NULL
}

normalize_yaml_text <- function(bytes) {
  if (length(bytes) == 0L) return("")
  utf8_bom <- as.raw(c(0xef, 0xbb, 0xbf))
  if (length(bytes) >= 3L && identical(bytes[seq_len(3L)], utf8_bom)) {
    bytes <- bytes[-seq_len(3L)]
  }
  text <- tryCatch(rawToChar(bytes), error = function(error) NULL)
  if (is.null(text) || !validUTF8(text)) return(NULL)
  # A UTF-8 BOM and CRLF/CR are accepted at the transport boundary but never
  # survive into the in-memory canonical representation.
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  gsub("\r", "\n", text, fixed = TRUE)
}

yaml_line_indent <- function(line) {
  match <- regexpr("^[ ]*", line, perl = TRUE)
  if (identical(match, -1L)) 0L else attr(match, "match.length")[[1L]]
}

strip_yaml_quoted_and_comments <- function(line, quote_state = NULL) {
  chars <- strsplit(line, "", fixed = TRUE)[[1L]]
  if (length(chars) == 0L) return(list(text = "", quote_state = quote_state))
  output <- chars
  quote <- quote_state
  escaped <- FALSE
  i <- 1L
  while (i <= length(chars)) {
    ch <- chars[[i]]
    if (!is.null(quote)) {
      output[[i]] <- " "
      if (identical(quote, "'")) {
        if (identical(ch, "'") && i < length(chars) && identical(chars[[i + 1L]], "'")) {
          output[[i + 1L]] <- " "
          i <- i + 2L
          next
        }
        if (identical(ch, "'")) quote <- NULL
      } else {
        if (escaped) {
          escaped <- FALSE
        } else if (identical(ch, "\\")) {
          escaped <- TRUE
        } else if (identical(ch, '"')) {
          quote <- NULL
        }
      }
      i <- i + 1L
      next
    }
    if (identical(ch, "'")) {
      quote <- "'"
      output[[i]] <- " "
    } else if (identical(ch, '"')) {
      quote <- '"'
      output[[i]] <- " "
    } else if (identical(ch, "#") && (i == 1L || grepl("[[:space:]]", chars[[i - 1L]]))) {
      output[i:length(chars)] <- " "
      break
    }
    i <- i + 1L
  }
  list(text = paste0(output, collapse = ""), quote_state = quote)
}

scan_yaml_features <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  quote_state <- NULL
  block_parent_indent <- NULL
  document_start_seen <- FALSE
  first_content_seen <- FALSE
  for (line_number in seq_along(lines)) {
    line <- lines[[line_number]]
    trimmed <- trimws(line)
    if (!is.null(block_parent_indent)) {
      if (identical(trimmed, "") || yaml_line_indent(line) > block_parent_indent) {
        next
      }
      block_parent_indent <- NULL
    }
    stripped <- strip_yaml_quoted_and_comments(line, quote_state)
    quote_state <- stripped$quote_state
    visible <- stripped$text
    trimmed_visible <- trimws(visible)
    if (identical(trimmed_visible, "")) next
    if (identical(trimmed_visible, "---")) {
      if (document_start_seen || first_content_seen) {
        return(list(ok = FALSE, message = "Multiple YAML documents are not supported."))
      }
      document_start_seen <- TRUE
      next
    }
    if (identical(trimmed_visible, "...")) {
      return(list(ok = FALSE, message = "YAML document end markers are not supported."))
    }
    first_content_seen <- TRUE
    # A block scalar protects all following indented source text from feature
    # scanning; this is important for custom SAS code containing '&' or '!'.
    if (grepl("(^|:)\\s*[|>]([+-])?\\s*$", trimmed_visible, perl = TRUE)) {
      block_parent_indent <- yaml_line_indent(line)
      next
    }
    if (grepl("(^|[[:space:],\\[\\]{])<<[[:space:]]*:", visible, perl = TRUE)) {
      return(list(ok = FALSE, message = "YAML merge keys are not supported."))
    }
    if (grepl("(^|[[:space:],\\[\\]{])&[A-Za-z0-9_-]+", visible, perl = TRUE)) {
      return(list(ok = FALSE, message = "YAML anchors are not supported."))
    }
    if (grepl("(^|[[:space:],\\[\\]{])\\*[A-Za-z0-9_-]+", visible, perl = TRUE)) {
      return(list(ok = FALSE, message = "YAML aliases are not supported."))
    }
    if (grepl("(^|[[:space:],\\[\\]{])![^[:space:],\\[\\]{}]+", visible, perl = TRUE)) {
      return(list(ok = FALSE, message = "YAML tags are not supported."))
    }
  }
  if (!is.null(quote_state)) {
    return(list(ok = FALSE, message = "Unterminated YAML quoted scalar."))
  }
  list(ok = TRUE)
}

parse_bundle_yaml <- function(input, registry = default_chunk_registry()) {
  bytes <- coerce_bundle_bytes(input)
  if (is.null(bytes) || length(bytes) == 0L) {
    return(new_bundle_import_result(
      FALSE, errors = list(new_error_item(
        "import", "bundle_input_missing", "Bundle input is missing.", "$")
    )))
  }
  text <- normalize_yaml_text(bytes)
  if (is.null(text)) {
    return(new_bundle_import_result(
      FALSE, errors = list(new_error_item(
        "import", "bundle_encoding_invalid", "Bundle input is not valid UTF-8.", "$")
    )))
  }
  feature_scan <- scan_yaml_features(text)
  if (!isTRUE(feature_scan$ok)) {
    return(new_bundle_import_result(
      FALSE, errors = list(new_error_item(
        "import", "bundle_yaml_invalid", feature_scan$message, "$")
    )))
  }
  parsed <- tryCatch(
    yaml::yaml.load(text, as.named.list = TRUE, eval.expr = FALSE),
    error = function(error) error
  )
  if (inherits(parsed, "error")) {
    parser_message <- conditionMessage(parsed)
    if (grepl("Duplicate map key", parser_message, fixed = TRUE)) {
      code <- "bundle_duplicate_key"
      message <- "A YAML mapping contains a duplicate key."
    } else {
      code <- "bundle_yaml_invalid"
      message <- "Bundle input is not valid YAML."
    }
    return(new_bundle_import_result(
      FALSE, errors = list(new_error_item("import", code, message, "$") )
    ))
  }
  decoded <- parse_bundle_value(parsed, registry)
  if (length(decoded$errors) > 0L) {
    return(new_bundle_import_result(FALSE, errors = decoded$errors))
  }
  new_bundle_import_result(TRUE, workspace = decoded$value, errors = list())
}

read_metadata_bundle <- parse_bundle_yaml

# Public aliases make the transport boundary discoverable without introducing
# a package-level dependency on a particular UI adapter name.
decode_metadata_bundle <- parse_bundle_yaml
parse_metadata_bundle <- parse_bundle_yaml

canonical_decimal <- function(value) {
  if (is.logical(value) || !is.numeric(value) || length(value) != 1L ||
      is.na(value) || !is.finite(value)) {
    stop("Canonical decimal requires one finite numeric value.", call. = FALSE)
  }
  if (value == 0) return("0")
  scientific <- sprintf("%.15g", as.numeric(value))
  scientific <- sub("^\\+", "", scientific)
  pieces <- strsplit(tolower(scientific), "e", fixed = TRUE)[[1L]]
  mantissa <- pieces[[1L]]
  exponent <- if (length(pieces) == 2L) as.integer(pieces[[2L]]) else 0L
  sign <- ""
  if (startsWith(mantissa, "-")) {
    sign <- "-"
    mantissa <- substring(mantissa, 2L)
  }
  mantissa_parts <- strsplit(mantissa, ".", fixed = TRUE)[[1L]]
  before_decimal <- nchar(mantissa_parts[[1L]])
  digits <- paste0(mantissa_parts, collapse = "")
  decimal_position <- before_decimal + exponent
  if (decimal_position <= 0L) {
    result <- paste0("0.", strrep("0", -decimal_position), digits)
  } else if (decimal_position >= nchar(digits)) {
    result <- paste0(digits, strrep("0", decimal_position - nchar(digits)))
  } else {
    result <- paste0(substr(digits, 1L, decimal_position), ".",
                     substring(digits, decimal_position + 1L))
  }
  if (grepl("\\.", result, fixed = TRUE)) {
    result <- sub("0+$", "", result)
    result <- sub("\\.$", "", result)
  }
  result <- sub("^0+([0-9])", "\\1", result)
  if (identical(result, "") || identical(result, "-0")) return("0")
  paste0(sign, result)
}

canonical_integer <- function(value) {
  if (is.logical(value) || !is.numeric(value) || length(value) != 1L ||
      is.na(value) || !is.finite(value) || value != floor(value)) {
    stop("Canonical integer requires one finite integer value.", call. = FALSE)
  }
  canonical_decimal(value)
}

yaml_single_quote <- function(value) {
  paste0("'", gsub("'", "''", value, fixed = TRUE), "'")
}

new_yaml_lines <- function() {
  e <- new.env(parent = emptyenv())
  e$lines <- character()
  e
}

yaml_append <- function(context, line) {
  context$lines <- c(context$lines, line)
  invisible(NULL)
}

yaml_indent <- function(level) strrep(" ", level)

yaml_scalar_lines <- function(indent, key, value, type = c("string", "integer", "number")) {
  type <- match.arg(type)
  prefix <- paste0(yaml_indent(indent), key, ": ")
  if (identical(type, "string")) {
    value <- gsub("\r\n", "\n", value, fixed = TRUE)
    value <- gsub("\r", "\n", value, fixed = TRUE)
    if (!grepl("\n", value, fixed = TRUE)) return(paste0(prefix, yaml_single_quote(value)))
    newline_count <- nchar(value) - nchar(sub("\\n+$", "", value))
    ends_newline <- endsWith(value, "\n")
    indicator <- if (!ends_newline) "|-" else if (newline_count > 1L) "|+" else "|"
    content_value <- sub("\\n+$", "", value)
    pieces <- if (identical(content_value, "")) character() else
      strsplit(content_value, "\n", fixed = TRUE)[[1L]]
    if (ends_newline && newline_count > 1L) {
      pieces <- c(pieces, rep("", newline_count - 1L))
    }
    result <- paste0(prefix, indicator)
    if (length(pieces) > 0L) {
      result <- c(result, paste0(yaml_indent(indent + 2L), pieces))
    }
    return(result)
  }
  scalar <- if (identical(type, "integer")) canonical_integer(value) else canonical_decimal(value)
  paste0(prefix, scalar)
}

yaml_emit_scalar <- function(context, indent, key, value, type = "string") {
  yaml_append(context, yaml_scalar_lines(indent, key, value, type))
}

yaml_emit_mapping <- function(context, indent, key, value, renderer) {
  if (length(value) == 0L) {
    yaml_append(context, paste0(yaml_indent(indent), key, ": {}"))
    return(invisible(NULL))
  }
  yaml_append(context, paste0(yaml_indent(indent), key, ":"))
  rendered <- renderer(value, indent + 2L)
  if (length(rendered) > 0L) yaml_append(context, rendered)
  invisible(NULL)
}

yaml_emit_sequence <- function(context, indent, key, value, renderer) {
  if (length(value) == 0L) {
    yaml_append(context, paste0(yaml_indent(indent), key, ": []"))
    return(invisible(NULL))
  }
  yaml_append(context, paste0(yaml_indent(indent), key, ":"))
  for (item in value) {
    rendered <- renderer(item, indent + 2L)
    if (length(rendered) == 0L) {
      yaml_append(context, paste0(yaml_indent(indent + 2L), "- {}"))
    } else {
      first_prefix <- yaml_indent(indent + 2L)
      first <- rendered[[1L]]
      if (startsWith(first, first_prefix)) {
        first <- substring(first, nchar(first_prefix) + 1L)
      }
      yaml_append(context, paste0(first_prefix, "- ", first))
      if (length(rendered) > 1L) {
        # The first mapping line shares the sequence marker's indentation;
        # every following mapping field is one level deeper than that marker.
        yaml_append(context, paste0("  ", rendered[-1L]))
      }
    }
  }
  invisible(NULL)
}

yaml_emit_scalar_sequence <- function(context, indent, key, value, type = "string") {
  if (length(value) == 0L) {
    yaml_append(context, paste0(yaml_indent(indent), key, ": []"))
    return(invisible(NULL))
  }
  yaml_append(context, paste0(yaml_indent(indent), key, ":"))
  for (item in value) {
    scalar_lines <- yaml_scalar_lines(indent + 2L, "_value_", item, type)
    first <- scalar_lines[[1L]]
    prefix <- paste0(yaml_indent(indent + 2L), "_value_: ")
    if (startsWith(first, prefix)) {
      first <- substring(first, nchar(prefix) + 1L)
    } else {
      first <- sub("^[^:]+: ", "", first)
    }
    yaml_append(context, paste0(yaml_indent(indent + 2L), "- ", first))
    if (length(scalar_lines) > 1L) yaml_append(context, scalar_lines[-1L])
  }
  invisible(NULL)
}

render_population_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "label", value$label)
  yaml_emit_scalar(context, indent, "expression", value$expression)
  context$lines
}

render_spanning_header_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "level", value$level, "integer")
  yaml_emit_scalar(context, indent, "label", value$label)
  context$lines
}

render_header_column_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "label", value$label)
  yaml_emit_scalar(context, indent, "condition", value$condition)
  yaml_emit_scalar(context, indent, "display_order", value$display_order, "integer")
  yaml_emit_scalar(context, indent, "width", value$width, "number")
  yaml_emit_scalar(context, indent, "alignment", value$alignment)
  for (field in c("spanning_header_1", "spanning_header_2")) {
    if (!is.null(value[[field]])) yaml_emit_scalar(context, indent, field, value[[field]])
  }
  context$lines
}

render_header_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "source_data", value$source_data)
  if (!is.null(value$spanning_headers) && length(value$spanning_headers) > 0L) {
    yaml_emit_sequence(context, indent, "spanning_headers", value$spanning_headers,
                       render_spanning_header_yaml)
  }
  yaml_emit_sequence(context, indent, "columns", value$columns, render_header_column_yaml)
  context$lines
}

render_custom_code_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  for (field in c("before", "after")) {
    if (!is.null(value[[field]]) && nzchar(trimws(value[[field]]))) {
      yaml_append(context, yaml_scalar_lines(indent, field, value[[field]], "string"))
    }
  }
  context$lines
}

render_table_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  for (field in c("id", "population_id", "header_id", "template_id")) {
    yaml_emit_scalar(context, indent, field, value[[field]])
  }
  if (!is.null(value$custom_code) && length(value$custom_code) > 0L) {
    yaml_emit_mapping(context, indent, "custom_code", value$custom_code, render_custom_code_yaml)
  }
  context$lines
}

render_statistic_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  if (!is.null(value$digits)) {
    if (is.character(value$digits)) yaml_emit_scalar(context, indent, "digits", value$digits)
    else yaml_emit_scalar(context, indent, "digits", value$digits, "integer")
  }
  context$lines
}

render_row_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "type", value$type)
  yaml_emit_scalar(context, indent, "label", value$label)
  if (!is.null(value$indent_level)) yaml_emit_scalar(context, indent, "indent_level",
                                                     value$indent_level, "integer")
  if (identical(value$type, "analysis")) {
    if (!is.null(value$condition)) yaml_emit_scalar(context, indent, "condition", value$condition)
    yaml_emit_sequence(context, indent, "statistics", value$statistics, render_statistic_yaml)
    yaml_emit_scalar(context, indent, "cell_format", value$cell_format)
  }
  context$lines
}

render_primitive_denominator_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "type", value$type)
  if (!is.null(value$variable)) yaml_emit_scalar(context, indent, "variable", value$variable)
  if (!is.null(value$expression)) yaml_emit_scalar(context, indent, "expression", value$expression)
  context$lines
}

render_source_contract_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "grain", value$grain)
  yaml_emit_scalar(context, indent, "subject_key", value$subject_key)
  if (!is.null(value$record_key)) {
    yaml_emit_scalar_sequence(context, indent, "record_key", value$record_key, "string")
  }
  yaml_emit_scalar(context, indent, "duplicate_policy", value$duplicate_policy)
  context$lines
}

render_hierarchical_denominator_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "scope", value$scope)
  yaml_emit_scalar(context, indent, "unit", value$unit)
  if (!is.null(value$variable)) yaml_emit_scalar(context, indent, "variable", value$variable)
  if (!is.null(value$expression)) yaml_emit_scalar(context, indent, "expression", value$expression)
  context$lines
}

render_result_sort_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_mapping(context, indent, "metric", value$metric, function(metric, metric_indent) {
    metric_context <- new_yaml_lines()
    for (field in c("analysis_id", "row_id", "statistic_id")) {
      yaml_emit_scalar(metric_context, metric_indent, field, metric[[field]])
    }
    metric_context$lines
  })
  yaml_emit_scalar_sequence(context, indent, "column_order", value$column_order, "integer")
  yaml_emit_scalar(context, indent, "direction", value$direction)
  context$lines
}

render_level_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "variable", value$variable)
  if (!is.null(value$label_variable)) yaml_emit_scalar(context, indent, "label_variable", value$label_variable)
  yaml_emit_scalar(context, indent, "order_variable", value$order_variable)
  yaml_emit_scalar(context, indent, "order_direction", value$order_direction)
  if (!is.null(value$result_sort)) yaml_emit_mapping(context, indent, "result_sort", value$result_sort,
                                                     render_result_sort_yaml)
  yaml_emit_scalar(context, indent, "node_role", value$node_role)
  if (!is.null(value$node_analysis_id)) yaml_emit_scalar(context, indent, "node_analysis_id", value$node_analysis_id)
  yaml_emit_scalar(context, indent, "missing_policy", value$missing_policy)
  if (!is.null(value$missing_label)) yaml_emit_scalar(context, indent, "missing_label", value$missing_label)
  context$lines
}

render_analysis_block_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  for (field in c("id", "anchor_level", "placement", "type", "counting_unit")) {
    yaml_emit_scalar(context, indent, field, value[[field]])
  }
  if (!is.null(value$distinct_key)) {
    yaml_emit_scalar_sequence(context, indent, "distinct_key", value$distinct_key, "string")
  }
  if (!is.null(value$analysis_variable)) yaml_emit_scalar(context, indent, "analysis_variable", value$analysis_variable)
  if (!is.null(value$denominator)) yaml_emit_mapping(context, indent, "denominator", value$denominator,
                                                     render_hierarchical_denominator_yaml)
  yaml_emit_sequence(context, indent, "rows", value$rows, render_row_yaml)
  context$lines
}

render_chunk_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_scalar(context, indent, "type", value$type)
  yaml_emit_scalar(context, indent, "source_data", value$source_data)
  if (!is.null(value$filter)) yaml_emit_scalar(context, indent, "filter", value$filter)
  if (identical(value$type, "continuous_summary")) {
    yaml_emit_scalar(context, indent, "analysis_variable", value$analysis_variable)
    yaml_emit_sequence(context, indent, "rows", value$rows, render_row_yaml)
  } else if (value$type %in% c("categorical_summary_nonexclusive", "categorical_summary_exclusive")) {
    yaml_emit_mapping(context, indent, "denominator", value$denominator,
                      render_primitive_denominator_yaml)
    yaml_emit_sequence(context, indent, "rows", value$rows, render_row_yaml)
  } else if (identical(value$type, "hierarchical_summary")) {
    yaml_emit_mapping(context, indent, "source_contract", value$source_contract,
                      render_source_contract_yaml)
    yaml_emit_sequence(context, indent, "levels", value$levels, render_level_yaml)
    yaml_emit_sequence(context, indent, "analysis_blocks", value$analysis_blocks,
                       render_analysis_block_yaml)
  }
  context$lines
}

render_template_yaml <- function(value, indent) {
  context <- new_yaml_lines()
  yaml_emit_scalar(context, indent, "id", value$id)
  yaml_emit_mapping(context, indent, "body", value$body, function(body, body_indent) {
    body_context <- new_yaml_lines()
    if (!is.null(body$stub_header)) yaml_emit_scalar(body_context, body_indent, "stub_header", body$stub_header)
    yaml_emit_sequence(body_context, body_indent, "chunks", body$chunks, render_chunk_yaml)
    body_context$lines
  })
  context$lines
}

canonical_yaml_text <- function(bundle, registry = default_chunk_registry()) {
  decoded <- parse_bundle_value(bundle, registry)
  if (length(decoded$errors) > 0L) {
    stop("Cannot encode an invalid metadata bundle.", call. = FALSE)
  }
  value <- decoded$value
  context <- new_yaml_lines()
  yaml_emit_scalar(context, 0L, "schema_version", value$schema_version, "integer")
  yaml_emit_sequence(context, 0L, "populations", value$populations, render_population_yaml)
  yaml_emit_sequence(context, 0L, "headers", value$headers, render_header_yaml)
  yaml_emit_sequence(context, 0L, "tables", value$tables, render_table_yaml)
  yaml_emit_sequence(context, 0L, "templates", value$templates, render_template_yaml)
  paste0(paste(context$lines, collapse = "\n"), "\n")
}

canonical_yaml_bytes <- function(bundle, registry = default_chunk_registry()) {
  new_canonical_bytes(canonical_yaml_text(bundle, registry))
}

encode_metadata_yaml <- canonical_yaml_bytes
serialize_metadata_yaml <- canonical_yaml_bytes

new_canonical_archive_bytes <- function(bytes) {
  if (!is.raw(bytes)) stop("Canonical archive requires raw bytes.", call. = FALSE)
  structure(list(bytes = bytes), class = c("CanonicalArchiveBytes", "list"))
}

as.character.CanonicalArchiveBytes <- function(x, ...) {
  stop("A canonical archive cannot be represented as character text.", call. = FALSE)
}

coerce_archive_bytes <- function(input) {
  if (inherits(input, "CanonicalArchiveBytes")) return(input$bytes)
  if (is.raw(input)) return(input)
  NULL
}

archive_error <- function(code, message, path = "$") {
  new_bundle_import_result(
    FALSE,
    errors = list(new_error_item("import", code, message, path))
  )
}

parse_yaml_document_text <- function(text, path = "$") {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    return(list(value = NULL, errors = list(new_error_item(
      "import", "bundle_encoding_invalid", "Bundle entry is not valid UTF-8.", path
    ))))
  }
  text <- normalize_yaml_text(charToRaw(text))
  if (is.null(text)) {
    return(list(value = NULL, errors = list(new_error_item(
      "import", "bundle_encoding_invalid", "Bundle entry is not valid UTF-8.", path
    ))))
  }
  feature_scan <- scan_yaml_features(text)
  if (!isTRUE(feature_scan$ok)) {
    return(list(value = NULL, errors = list(new_error_item(
      "import", "bundle_yaml_invalid", feature_scan$message, path
    ))))
  }
  parsed <- tryCatch(
    yaml::yaml.load(text, as.named.list = TRUE, eval.expr = FALSE),
    error = function(error) error
  )
  if (inherits(parsed, "error")) {
    parser_message <- conditionMessage(parsed)
    code <- if (grepl("Duplicate map key", parser_message, fixed = TRUE)) {
      "bundle_duplicate_key"
    } else {
      "bundle_yaml_invalid"
    }
    message <- if (identical(code, "bundle_duplicate_key")) {
      "A YAML mapping contains a duplicate key."
    } else {
      "Bundle entry is not valid YAML."
    }
    return(list(value = NULL, errors = list(new_error_item(
      "import", code, message, path
    ))))
  }
  list(value = parsed, errors = list())
}

parse_manifest_yaml <- function(text) {
  parsed <- parse_yaml_document_text(text, "$.manifest.yaml")
  if (length(parsed$errors) > 0L) return(parsed)
  collector <- new_error_collector()
  if (!check_mapping(parsed$value, "$.manifest.yaml", collector,
                     "schema_version", "schema_version")) {
    return(list(value = NULL, errors = error_items(collector)))
  }
  schema_version <- parse_integer_value(
    get_field(parsed$value, "schema_version"),
    "$.manifest.yaml.schema_version", collector, "schema_version", min_value = 1
  )
  if (!is.null(schema_version) && !identical(as.integer(schema_version), 1L)) {
    add_error(collector, "import", "bundle_schema_unsupported",
              sprintf("Schema version '%s' is not supported.", schema_version),
              "$.manifest.yaml.schema_version")
    schema_version <- NULL
  }
  errors <- error_items(collector)
  if (length(errors) > 0L || is.null(schema_version)) {
    return(list(value = NULL, errors = errors))
  }
  list(value = list(schema_version = schema_version), errors = list())
}

parse_catalog_yaml <- function(text, collection_name, parser) {
  path <- paste0("$.", collection_name, ".yaml")
  parsed <- parse_yaml_document_text(text, path)
  if (length(parsed$errors) > 0L) return(parsed)
  collector <- new_error_collector()
  if (!check_mapping(parsed$value, path, collector, collection_name, collection_name)) {
    return(list(value = NULL, errors = error_items(collector)))
  }
  raw <- parse_collection_raw(
    get_field(parsed$value, collection_name),
    paste0(path, ".", collection_name), collector, collection_name,
    required = TRUE, allow_empty = TRUE
  )
  objects <- list()
  if (!is.null(raw)) {
    for (i in seq_along(raw$items)) {
      item_path <- error_path_index(paste0(path, ".", collection_name), i - 1L)
      value <- parser(raw$items[[i]], item_path, collector)
      if (!is.null(value)) objects[[length(objects) + 1L]] <- value
    }
    if (length(objects) == length(raw$items)) {
      check_unique_ids(
        objects,
        lapply(seq_along(objects), function(i)
          error_path_index(paste0(path, ".", collection_name), i - 1L)),
        collector
      )
    }
  }
  errors <- error_items(collector)
  if (length(errors) > 0L || is.null(raw) || length(objects) != length(raw$items)) {
    return(list(value = NULL, errors = errors))
  }
  result <- list()
  result[[collection_name]] <- objects
  list(value = result, errors = list())
}

archive_entry_class <- function(name) {
  if (identical(name, "manifest.yaml")) return("manifest")
  if (identical(name, "populations.yaml")) return("populations")
  if (identical(name, "headers.yaml")) return("headers")
  if (grepl("^tables/[^/]+\\.yaml$", name, perl = TRUE)) return("table")
  if (grepl("^templates/[^/]+\\.yaml$", name, perl = TRUE)) return("template")
  NULL
}

validate_archive_entries <- function(entries) {
  names <- entries$filename
  if (length(names) == 0L) {
    return(list(error = new_error_item(
      "import", "bundle_entry_missing", "Metadata archive contains no entries.", "$"
    )))
  }
  if (anyDuplicated(names)) {
    duplicate <- names[[which(duplicated(names))[1L]]]
    return(list(error = new_error_item(
      "import", "bundle_entry_duplicate", "Metadata archive contains a duplicate entry.",
      paste0("$.", duplicate)
    )))
  }
  if (any(entries$type != "file")) {
    return(list(error = new_error_item(
      "import", "bundle_entry_invalid", "Metadata archive contains a non-file entry.", "$"
    )))
  }
  for (name in names) {
    invalid_path <- startsWith(name, "/") || grepl("\\\\", name, fixed = TRUE) ||
      grepl("(^|/)\\.{1,2}(/|$)", name, perl = TRUE) ||
      grepl("^[A-Za-z]:", name, perl = TRUE)
    if (invalid_path || is.null(archive_entry_class(name))) {
      return(list(error = new_error_item(
        "import", "bundle_entry_invalid", "Metadata archive contains an unsupported entry.",
        paste0("$.", name)
      )))
    }
  }
  list(error = NULL)
}

archive_file_id <- function(name) sub("\\.yaml$", "", basename(name))

read_archive_entries <- function(bytes) {
  if (is.null(bytes) || length(bytes) == 0L) {
    return(list(error = new_error_item("import", "bundle_input_missing",
                                       "Bundle input is missing.", "$")))
  }
  temp_root <- tempfile("tfl_archive_")
  dir.create(temp_root)
  on.exit(unlink(temp_root, recursive = TRUE, force = TRUE), add = TRUE)
  zip_path <- file.path(temp_root, "bundle.zip")
  writeBin(bytes, zip_path)
  listing <- tryCatch(zip::zip_list(zip_path), error = function(error) error)
  if (inherits(listing, "error")) {
    return(list(error = new_error_item("import", "bundle_archive_invalid",
                                       "Bundle input is not a valid ZIP archive.", "$")))
  }
  validation <- validate_archive_entries(listing)
  if (!is.null(validation$error)) return(list(error = validation$error))
  extracted <- tryCatch({
    zip::unzip(zip_path, files = listing$filename, overwrite = TRUE,
               junkpaths = FALSE, exdir = temp_root)
    lapply(listing$filename, function(name) {
      path <- file.path(temp_root, name)
      info <- file.info(path)
      if (is.na(info$size) || info$isdir) stop("archive entry extraction failed")
      readBin(path, "raw", n = info$size)
    })
  }, error = function(error) error)
  if (inherits(extracted, "error")) {
    return(list(error = new_error_item("import", "bundle_archive_invalid",
                                       "Bundle archive entries could not be read.", "$")))
  }
  names(extracted) <- listing$filename
  list(entries = extracted, error = NULL)
}

parse_bundle_archive <- function(input, registry = default_chunk_registry()) {
  bytes <- coerce_archive_bytes(input)
  loaded <- read_archive_entries(bytes)
  if (!is.null(loaded$error)) return(new_bundle_import_result(FALSE, errors = list(loaded$error)))
  entries <- loaded$entries
  required <- c("manifest.yaml", "populations.yaml", "headers.yaml")
  missing <- setdiff(required, names(entries))
  if (length(missing) > 0L) {
    return(archive_error("bundle_entry_missing", "Metadata archive is missing a required entry.",
                         paste0("$.", missing[[1L]])))
  }
  manifest <- parse_manifest_yaml(rawToChar(entries[["manifest.yaml"]]))
  if (length(manifest$errors) > 0L) return(new_bundle_import_result(FALSE, errors = manifest$errors))
  populations <- parse_catalog_yaml(
    rawToChar(entries[["populations.yaml"]]), "populations", parse_population_value
  )
  headers <- parse_catalog_yaml(
    rawToChar(entries[["headers.yaml"]]), "headers", parse_header_value
  )
  errors <- c(populations$errors, headers$errors)
  tables <- list()
  templates <- list()
  table_names <- sort(names(entries)[grepl("^tables/[^/]+\\.yaml$", names(entries), perl = TRUE)])
  template_names <- sort(names(entries)[grepl("^templates/[^/]+\\.yaml$", names(entries), perl = TRUE)])
  for (name in table_names) {
    parsed <- parse_yaml_document_text(rawToChar(entries[[name]]), paste0("$.", name))
    if (length(parsed$errors) > 0L) {
      errors <- c(errors, parsed$errors)
      next
    }
    collector <- new_error_collector()
    value <- parse_table_value(parsed$value, paste0("$.", name), collector)
    errors <- c(errors, error_items(collector))
    if (!is.null(value)) {
      if (!identical(value$id, archive_file_id(name))) {
        errors <- c(errors, list(new_error_item(
          "import", "bundle_file_identity_invalid",
          "Table file name does not match the object ID.", paste0("$.", name, ".id")
        )))
      } else tables[[length(tables) + 1L]] <- value
    }
  }
  for (name in template_names) {
    parsed <- parse_yaml_document_text(rawToChar(entries[[name]]), paste0("$.", name))
    if (length(parsed$errors) > 0L) {
      errors <- c(errors, parsed$errors)
      next
    }
    collector <- new_error_collector()
    value <- parse_template_value(parsed$value, paste0("$.", name), collector, registry)
    errors <- c(errors, error_items(collector))
    if (!is.null(value)) {
      if (!identical(value$id, archive_file_id(name))) {
        errors <- c(errors, list(new_error_item(
          "import", "bundle_file_identity_invalid",
          "Template file name does not match the object ID.", paste0("$.", name, ".id")
        )))
      } else templates[[length(templates) + 1L]] <- value
    }
  }
  if (length(errors) > 0L) return(new_bundle_import_result(FALSE, errors = errors))
  value <- list(
    schema_version = manifest$value$schema_version,
    populations = populations$value$populations,
    headers = headers$value$headers,
    tables = tables,
    templates = templates
  )
  decoded <- parse_bundle_value(value, registry)
  if (length(decoded$errors) > 0L) return(new_bundle_import_result(FALSE, errors = decoded$errors))
  new_bundle_import_result(TRUE, workspace = decoded$value, errors = list())
}

encode_archive_texts <- function(bundle, registry = default_chunk_registry()) {
  decoded <- parse_bundle_value(bundle, registry)
  if (length(decoded$errors) > 0L) stop("Cannot encode an invalid metadata bundle.", call. = FALSE)
  value <- decoded$value
  result <- c(
    `manifest.yaml` = paste0("schema_version: ", canonical_integer(value$schema_version), "\n"),
    `populations.yaml` = paste0(
      paste(yaml_render_catalog("populations", value$populations, render_population_yaml), collapse = "\n"), "\n"
    ),
    `headers.yaml` = paste0(
      paste(yaml_render_catalog("headers", value$headers, render_header_yaml), collapse = "\n"), "\n"
    )
  )
  for (item in value$tables[order(vapply(value$tables, `[[`, "", "id") )]) {
    result[[paste0("tables/", item$id, ".yaml")]] <- paste0(
      paste(render_table_yaml(item, 0L), collapse = "\n"), "\n"
    )
  }
  for (item in value$templates[order(vapply(value$templates, `[[`, "", "id") )]) {
    result[[paste0("templates/", item$id, ".yaml")]] <- paste0(
      paste(render_template_yaml(item, 0L), collapse = "\n"), "\n"
    )
  }
  result
}

yaml_render_catalog <- function(name, values, renderer) {
  context <- new_yaml_lines()
  yaml_emit_sequence(context, 0L, name, values, renderer)
  context$lines
}

canonical_archive_bytes <- function(bundle, registry = default_chunk_registry()) {
  texts <- encode_archive_texts(bundle, registry)
  staging <- tempfile("tfl_archive_out_")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  for (name in names(texts)) {
    path <- file.path(staging, name)
    parent <- dirname(path)
    if (!dir.exists(parent)) dir.create(parent, recursive = TRUE)
    writeBin(charToRaw(enc2utf8(texts[[name]])), path)
    Sys.setFileTime(path, as.POSIXct("1980-01-01", tz = "UTC"))
  }
  zip_path <- tempfile("tfl_bundle_", fileext = ".zip")
  on.exit(unlink(zip_path, force = TRUE), add = TRUE)
  working_directory <- getwd()
  on.exit(setwd(working_directory), add = TRUE)
  setwd(staging)
  zip::zipr(zip_path, files = names(texts), recurse = FALSE,
            include_directories = FALSE, root = ".", mode = "mirror")
  new_canonical_archive_bytes(readBin(zip_path, "raw", n = file.info(zip_path)$size))
}

encode_metadata_archive <- canonical_archive_bytes
serialize_metadata_archive <- canonical_archive_bytes

# Public bundle aliases operate on the ZIP transport. The YAML helpers above
# remain available for individual archive entries and logical value fixtures.
encode_metadata_bundle <- canonical_archive_bytes
serialize_metadata_bundle <- canonical_archive_bytes

try_encode_metadata_bundle <- function(bundle, registry = default_chunk_registry()) {
  result <- tryCatch(
    list(passed = TRUE, bytes = canonical_archive_bytes(bundle, registry), errors = list()),
    error = function(error) list(
      passed = FALSE,
      bytes = NULL,
      errors = list(new_error_item("import", "bundle_structure_invalid",
                                   "Metadata bundle cannot be encoded.", "$") )
    )
  )
  result
}
