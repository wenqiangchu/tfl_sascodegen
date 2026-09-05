# Pure host-side SAS source assembly. Emitters provide chunk-specific source.

new_generation_request <- function(workspace_snapshot, table_id,
                                   registry = default_chunk_registry()) {
  structure(
    list(workspace_snapshot = workspace_snapshot, table_id = table_id, registry = registry),
    class = c("GenerationRequest", "list")
  )
}

new_generation_result <- function(passed, source = NULL, errors = list()) {
  structure(
    list(passed = isTRUE(passed), source = if (isTRUE(passed)) source else NULL,
         errors = errors),
    class = c("GenerationResult", "list")
  )
}

new_source_section <- function(section_id, kind, owner_id, order, text) {
  values <- list(section_id = section_id, kind = kind, owner_id = owner_id, text = text)
  if (any(!vapply(values, function(value) {
    is.character(value) && length(value) == 1L && !is.na(value)
  }, logical(1L))) || !is.numeric(order) || length(order) != 1L || is.na(order)) {
    stop("SourceSection fields are invalid.", call. = FALSE)
  }
  structure(c(values[1:3], list(order = as.integer(order)), values[4]),
            class = c("SourceSection", "list"))
}

new_emitter_output <- function(sections, statistic_dataset, render_dataset) {
  structure(
    list(sections = sections, statistic_dataset = statistic_dataset,
         render_dataset = render_dataset),
    class = c("EmitterOutput", "list")
  )
}

generation_error <- function(code, message, path = "$") {
  new_error_item("generation", code, message, path)
}

find_object_by_id <- function(values, id) {
  matches <- which(vapply(values, function(value) identical(value$id, id), logical(1L)))
  if (length(matches) == 0L) NULL else values[[matches[[1L]]]]
}

resolve_generation_request <- function(request) {
  if (!inherits(request, "GenerationRequest") ||
      !is.character(request$table_id) || length(request$table_id) != 1L ||
      is.na(request$table_id) || !nzchar(request$table_id) ||
      !inherits(request$registry, "ChunkRegistry")) {
    return(list(value = NULL, errors = list(generation_error(
      "generation_contract_invalid", "Generation request is invalid.", "$"
    ))))
  }
  decoded <- tryCatch(
    parse_bundle_value(request$workspace_snapshot, request$registry),
    error = function(error) NULL
  )
  if (is.null(decoded) || length(decoded$errors) > 0L) {
    return(list(value = NULL, errors = list(generation_error(
      "generation_contract_invalid", "Workspace snapshot is invalid.", "$.workspace_snapshot"
    ))))
  }
  snapshot <- decoded$value
  table_index <- which(vapply(snapshot$tables, function(table) {
    identical(table$id, request$table_id)
  }, logical(1L)))
  if (length(table_index) == 0L) {
    return(list(value = NULL, errors = list(generation_error(
      "generation_table_missing", sprintf("Table '%s' was not found.", request$table_id),
      "$.table_id"
    ))))
  }
  table <- snapshot$tables[[table_index[[1L]]]]
  references <- list(
    population = list(values = snapshot$populations, id = table$population_id,
                      path = sprintf("$.tables[%d].population_id", table_index[[1L]] - 1L)),
    header = list(values = snapshot$headers, id = table$header_id,
                  path = sprintf("$.tables[%d].header_id", table_index[[1L]] - 1L)),
    template = list(values = snapshot$templates, id = table$template_id,
                    path = sprintf("$.tables[%d].template_id", table_index[[1L]] - 1L))
  )
  resolved <- list()
  errors <- list()
  for (name in names(references)) {
    reference <- references[[name]]
    value <- find_object_by_id(reference$values, reference$id)
    if (is.null(value)) {
      errors[[length(errors) + 1L]] <- generation_error(
        "generation_reference_missing",
        sprintf("Referenced %s '%s' was not found.", name, reference$id), reference$path
      )
    } else {
      resolved[[name]] <- value
    }
  }
  if (length(errors) > 0L) return(list(value = NULL, errors = errors))
  list(value = structure(
    list(snapshot = snapshot, table = table, population = resolved$population,
         header = resolved$header, template = resolved$template,
         registry = request$registry),
    class = c("ResolvedTableInput", "list")
  ), errors = list())
}

batch_definition_signature <- function(definition) {
  list(
    batch_type = definition$batch_contract$batch_type,
    data_grain = definition$data_grain,
    merge_contract = definition$merge_contract,
    analysis_contract = definition$analysis_contract
  )
}

batch_dataset_names <- function(definition, batch_order) {
  suffix <- sprintf("%03d", batch_order)
  batch_type <- definition$batch_contract$batch_type
  prefix <- if (identical(batch_type, "continuous")) "C" else if (
    batch_type %in% c("categorical_nonexclusive", "categorical_exclusive")
  ) "K" else "H"
  result <- list(
    input_dataset = paste0("_TFL_", prefix, "IN_", suffix),
    raw_dataset = paste0("_TFL_", prefix, "RAW_", suffix),
    statistic_dataset = paste0("_TFL_STAT_", suffix),
    render_dataset = paste0("_TFL_REND_", suffix)
  )
  if (identical(batch_type, "continuous")) {
    result$precision_dataset <- paste0("_TFL_CPREC_", suffix)
  }
  result
}

plan_primitive_batches <- function(resolved) {
  groups <- list()
  errors <- list()
  chunks <- resolved$template$body$chunks
  for (chunk_order in seq_along(chunks)) {
    chunk <- chunks[[chunk_order]]
    definition <- chunk_registry_lookup(resolved$registry, chunk$type)
    path <- sprintf("$.templates[%s].body.chunks[%d]", resolved$template$id,
                    chunk_order - 1L)
    if (is.null(definition) || is.null(definition$emitter)) {
      errors[[length(errors) + 1L]] <- generation_error(
        "generation_emitter_unavailable",
        sprintf("No source emitter is available for chunk type '%s'.", chunk$type), path
      )
      next
    }
    signature <- batch_definition_signature(definition)
    group_index <- NULL
    if (isTRUE(definition$batch_contract$batchable)) {
      candidates <- which(vapply(groups, function(group) {
        isTRUE(group$batchable) && identical(group$signature, signature)
      }, logical(1L)))
      if (length(candidates) > 0L) group_index <- candidates[[1L]]
    }
    entry <- list(chunk_order = as.integer(chunk_order), chunk = chunk)
    if (is.null(group_index)) {
      groups[[length(groups) + 1L]] <- list(
        batchable = isTRUE(definition$batch_contract$batchable),
        signature = signature, definition = definition, entries = list(entry)
      )
    } else {
      groups[[group_index]]$entries[[length(groups[[group_index]]$entries) + 1L]] <- entry
    }
  }
  if (length(errors) > 0L) return(list(value = NULL, errors = errors))
  plans <- lapply(seq_along(groups), function(batch_order) {
    group <- groups[[batch_order]]
    names <- batch_dataset_names(group$definition, batch_order)
    structure(c(list(
      batch_order = as.integer(batch_order),
      chunk_type = group$definition$type_id,
      chunk_orders = vapply(group$entries, `[[`, integer(1L), "chunk_order"),
      chunks = lapply(group$entries, `[[`, "chunk"),
      header_columns = resolved$header$columns,
      membership_dataset = "_TFL_MEM_001",
      definition = group$definition
    ), names), class = c("PrimitiveBatchPlan", "list"))
  })
  list(value = plans, errors = list())
}

sas_character_literal <- function(value) {
  paste0("'", gsub("'", "''", value, fixed = TRUE), "'")
}

population_header_sections <- function(resolved) {
  population_text <- paste(
    "/* Select the table population. */",
    "data _TFL_POP_001;",
    paste0("  set ", resolved$header$source_data, ";"),
    paste0("  if not (", resolved$population$expression, ") then delete;"),
    "run;", sep = "\n"
  )
  columns <- resolved$header$columns
  id_length <- max(1L, nchar(vapply(columns, `[[`, "", "id"), type = "bytes"))
  column_steps <- vapply(seq_along(columns), function(index) {
    column <- columns[[index]]
    paste(
      "/* Derive header column membership. */",
      paste0("data _TFL_HCOL_", sprintf("%03d", index), ";"),
      paste0("  length header_column_id $", id_length, ";"),
      "  set _TFL_POP_001;",
      paste0("  if (", column$condition, ");"),
      paste0("  header_column_id = ", sas_character_literal(column$id), ";"),
      paste0("  column_order = ", index, ";"),
      "  keep USUBJID header_column_id column_order;",
      "run;", sep = "\n"
    )
  }, character(1L))
  membership_text <- paste(
    c(column_steps, "/* Assemble header membership. */", "data _TFL_MEM_001;",
      paste0("  set ", paste0("_TFL_HCOL_", sprintf("%03d", seq_along(columns)),
                                collapse = " "), ";"), "run;"),
    collapse = "\n"
  )
  list(
    new_source_section("population", "population", resolved$population$id, 20L,
                       population_text),
    new_source_section("membership", "membership", resolved$header$id, 30L,
                       membership_text)
  )
}

validate_emitter_output <- function(output, owner_id) {
  valid_string <- function(value) is.character(value) && length(value) == 1L &&
    !is.na(value) && nzchar(value)
  if (!inherits(output, "EmitterOutput") || !is.list(output$sections) ||
      !all(vapply(output$sections, inherits, logical(1L), "SourceSection")) ||
      !valid_string(output$statistic_dataset) || !valid_string(output$render_dataset)) {
    return(generation_error(
      "generation_contract_invalid",
      sprintf("Emitter output for '%s' is invalid.", owner_id), "$.emitter_output"
    ))
  }
  NULL
}

assemble_source_sections <- function(sections) {
  ordered <- sections[order(vapply(sections, `[[`, integer(1L), "order"))]
  paste(vapply(ordered, `[[`, "", "text"), collapse = "\n\n")
}

generate_sas_source <- function(request) {
  resolved_result <- resolve_generation_request(request)
  if (length(resolved_result$errors) > 0L) {
    return(new_generation_result(FALSE, errors = resolved_result$errors))
  }
  resolved <- resolved_result$value
  planned <- plan_primitive_batches(resolved)
  if (length(planned$errors) > 0L) {
    return(new_generation_result(FALSE, errors = planned$errors))
  }
  sections <- list()
  custom_code <- resolved$table$custom_code %||% list()
  if (!is.null(custom_code$before)) {
    sections[[length(sections) + 1L]] <- new_source_section(
      "custom_before", "custom", resolved$table$id, 10L, custom_code$before
    )
  }
  sections <- c(sections, population_header_sections(resolved))
  outputs <- list()
  for (index in seq_along(planned$value)) {
    plan <- planned$value[[index]]
    output <- tryCatch(
      plan$definition$emitter(plan = plan, resolved = resolved),
      error = function(error) NULL
    )
    output_error <- validate_emitter_output(output, plan$chunk_type)
    if (!is.null(output_error)) {
      return(new_generation_result(FALSE, errors = list(output_error)))
    }
    for (section_index in seq_along(output$sections)) {
      output$sections[[section_index]]$order <- 100L + index * 100L + section_index
    }
    sections <- c(sections, output$sections)
    outputs[[length(outputs) + 1L]] <- output
  }
  assembly_text <- paste(
    "/* Assemble table rows and cells in template order. */",
    "data _TFL_ASM_001;",
    paste0("  set ", paste(vapply(outputs, `[[`, "", "render_dataset"), collapse = " "), ";"),
    "run;", sep = "\n"
  )
  sections[[length(sections) + 1L]] <- new_source_section(
    "table_assembly", "assembly", resolved$table$id, 100000L, assembly_text
  )
  if (!is.null(custom_code$after)) {
    sections[[length(sections) + 1L]] <- new_source_section(
      "custom_after", "custom", resolved$table$id, 100010L, custom_code$after
    )
  }
  new_generation_result(TRUE, source = assemble_source_sections(sections), errors = list())
}

generate_table_source <- function(workspace_snapshot, table_id,
                                  registry = default_chunk_registry()) {
  generate_sas_source(new_generation_request(workspace_snapshot, table_id, registry))
}
