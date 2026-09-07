# Session-owned metadata workspace and draft lifecycle.

workspace_metadata_fields <- c(
  "schema_version", "populations", "headers", "tables", "templates"
)
workspace_document_types <- c(
  "population", "header", "table", "template", "chunk", "level",
  "analysis_block", "row"
)

clone_metadata_value <- function(value) {
  if (!is.list(value)) return(value)
  result <- lapply(value, clone_metadata_value)
  names(result) <- names(value)
  attributes(result) <- attributes(value)
  result
}

is_workspace <- function(value) inherits(value, "MetadataWorkspace")

workspace_metadata_value <- function(workspace) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  result <- lapply(workspace_metadata_fields, function(field) {
    clone_metadata_value(workspace[[field]])
  })
  names(result) <- workspace_metadata_fields
  result
}

workspace_saved_snapshot <- workspace_metadata_value

workspace_revision_value <- function(workspace) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  clone_metadata_value(workspace$revision)
}

workspace_is_dirty <- function(workspace) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  !is.null(workspace$active_draft) && isTRUE(workspace$active_draft$dirty)
}

# Canonical draft state used by adapters to distinguish a real edit from an
# update draft whose value was returned to its saved base.
workspace_draft_status <- function(workspace) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  draft <- workspace$active_draft
  if (is.null(draft)) return("none")
  if (identical(draft$operation, "create")) return("create_pending")
  if (identical(draft$operation, "update") && !isTRUE(draft$dirty)) return("update_clean")
  if (identical(draft$operation, "update")) return("update_dirty")
  if (identical(draft$operation, "delete")) return("delete_pending")
  "unknown"
}

workspace_same_target <- function(left, right) {
  fields <- c("document_type", "document_id", "template_id", "chunk_id",
              "level_id", "analysis_id", "row_id", "parent_id")
  all(vapply(fields, function(field) {
    identical(left[[field]], right[[field]])
  }, logical(1L)))
}

workspace_active_draft_conflict <- function(workspace, target, operation) {
  draft <- workspace$active_draft
  if (is.null(draft)) return(NULL)
  same <- identical(draft$operation, operation) &&
    workspace_same_target(draft$target, target)
  if (same) return(NULL)
  if (isTRUE(draft$dirty)) {
    return(workspace_error(
      "workspace_draft_dirty",
      "A different active draft contains unsaved changes.",
      "$.active_draft"
    ))
  }
  NULL
}

workspace_error <- function(code, message, path = "$") {
  new_error_item("workspace", code, message, path)
}

workspace_error_result <- function(workspace, errors, value = NULL, changed = FALSE) {
  structure(
    list(
      passed = FALSE,
      workspace = workspace,
      value = value,
      changed = isTRUE(changed),
      errors = errors
    ),
    class = c("WorkspaceResult", "list")
  )
}

workspace_ok_result <- function(workspace, value = NULL, changed = FALSE,
                                errors = list()) {
  structure(
    list(
      passed = TRUE,
      workspace = workspace,
      value = value,
      changed = isTRUE(changed),
      errors = errors
    ),
    class = c("WorkspaceResult", "list")
  )
}

workspace_with_metadata <- function(workspace, metadata,
                                    active_draft = NULL,
                                    parse_diagnostic = workspace$parse_diagnostic,
                                    revision = workspace$revision) {
  result <- lapply(workspace_metadata_fields, function(field) {
    clone_metadata_value(metadata[[field]])
  })
  names(result) <- workspace_metadata_fields
  result$active_draft <- clone_metadata_value(active_draft)
  result$parse_diagnostic <- clone_metadata_value(parse_diagnostic)
  result$revision <- clone_metadata_value(revision)
  class(result) <- c("MetadataWorkspace", "list")
  result
}

new_metadata_workspace <- function(bundle = new_metadata_bundle(),
                                    registry = default_chunk_registry()) {
  decoded <- parse_bundle_value(bundle, registry)
  if (length(decoded$errors) > 0L) {
    stop("Cannot create a workspace from an invalid metadata bundle.", call. = FALSE)
  }
  metadata <- decoded$value
  result <- workspace_with_metadata(
    workspace = list(parse_diagnostic = list(), revision = list()),
    metadata = metadata,
    active_draft = NULL,
    parse_diagnostic = list(),
    revision = list(saved_revision = 0L, draft_base_revision = NULL)
  )
  result
}

new_empty_workspace <- function(registry = default_chunk_registry()) {
  new_metadata_workspace(new_metadata_bundle(), registry)
}

workspace_revision <- function(workspace) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  workspace$revision$saved_revision
}

workspace_draft_value <- function(workspace) {
  if (!is_workspace(workspace)) {
    stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  }
  if (is.null(workspace$active_draft)) return(NULL)
  clone_metadata_value(workspace$active_draft$draft_value)
}

workspace_target <- function(document_type, document_id = NULL,
                             template_id = NULL, chunk_id = NULL,
                             level_id = NULL, analysis_id = NULL,
                             row_id = NULL, parent_id = NULL) {
  if (is.list(document_type)) {
    target <- clone_metadata_value(document_type)
    if (is.null(target$document_type)) {
      target$document_type <- target$kind %||% target$type
    }
    if (is.null(target$document_id)) {
      target$document_id <- target$id
    }
    if (is.null(target$analysis_id)) {
      target$analysis_id <- target$analysis_block_id
    }
    if (is.null(target$level_id) && !is.null(target$level)) {
      target$level_id <- target$level
    }
    if (is.null(target$row_id) && identical(target$document_type, "row")) {
      target$row_id <- target$document_id
    }
    if (is.null(target$chunk_id) && identical(target$document_type, "chunk")) {
      target$chunk_id <- target$document_id
    }
    if (is.null(target$analysis_id) &&
        identical(target$document_type, "analysis_block")) {
      target$analysis_id <- target$document_id
    }
    if (is.null(target$level_id) && identical(target$document_type, "level")) {
      target$level_id <- target$document_id
    }
    return(target)
  }
  if (!is.character(document_type) || length(document_type) != 1L) {
    stop("document_type must be a single string or target list.", call. = FALSE)
  }
  target <- list(document_type = document_type)
  if (!is.null(document_id)) target$document_id <- document_id
  if (!is.null(template_id)) target$template_id <- template_id
  if (!is.null(chunk_id)) target$chunk_id <- chunk_id
  if (!is.null(level_id)) target$level_id <- level_id
  if (!is.null(analysis_id)) target$analysis_id <- analysis_id
  if (!is.null(row_id)) target$row_id <- row_id
  if (!is.null(parent_id)) target$parent_id <- parent_id
  if (identical(document_type, "row") && is.null(target$row_id)) {
    target$row_id <- document_id
  }
  if (identical(document_type, "chunk") && is.null(target$chunk_id)) {
    target$chunk_id <- document_id
  }
  if (identical(document_type, "analysis_block") && is.null(target$analysis_id)) {
    target$analysis_id <- document_id
  }
  if (identical(document_type, "level") && is.null(target$level_id)) {
    target$level_id <- document_id
  }
  target
}

workspace_validate_target <- function(target, allow_missing_id = FALSE) {
  if (!is.list(target) || !is.character(target$document_type) ||
      length(target$document_type) != 1L ||
      !target$document_type %in% workspace_document_types) {
    return(workspace_error(
      "workspace_target_invalid", "Target document type is invalid.", "$.target"
    ))
  }
  if (!allow_missing_id &&
      (is.null(target$document_id) || !is.character(target$document_id) ||
       length(target$document_id) != 1L || is.na(target$document_id) ||
       !nzchar(target$document_id))) {
    return(workspace_error(
      "workspace_target_invalid", "Target document ID is required.", "$.target.document_id"
    ))
  }
  NULL
}

workspace_validate_position <- function(position, allow_infinite = TRUE,
                                         path = "$.position") {
  valid_scalar <- is.numeric(position) && !is.logical(position) &&
    length(position) == 1L && !is.na(position)
  if (!valid_scalar) {
    return(workspace_error(
      "workspace_position_invalid", "Position must be a single numeric value.", path
    ))
  }
  if (is.infinite(position)) {
    if (isTRUE(allow_infinite) && position > 0) return(NULL)
    return(workspace_error(
      "workspace_position_invalid", "Position must be a finite integer.", path
    ))
  }
  if (position != floor(position) || position < 1) {
    return(workspace_error(
      "workspace_position_invalid", "Position must be a positive integer.", path
    ))
  }
  NULL
}

workspace_path_get <- function(value, path) {
  result <- value
  if (length(path) == 0L) return(result)
  for (key in path) result <- result[[key]]
  result
}

workspace_path_replace <- function(value, path, replacement) {
  if (length(path) == 0L) return(clone_metadata_value(replacement))
  key <- path[[1L]]
  if (length(path) == 1L) {
    value[[key]] <- clone_metadata_value(replacement)
  } else {
    value[[key]] <- workspace_path_replace(value[[key]], path[-1L], replacement)
  }
  value
}

workspace_path_remove <- function(value, path) {
  if (length(path) == 0L) {
    stop("Cannot remove the root value.", call. = FALSE)
  }
  key <- path[[1L]]
  if (length(path) == 1L) {
    value <- value[-key]
    if (!is.null(names(value)) && all(!nzchar(names(value)))) names(value) <- NULL
    return(value)
  }
  value[[key]] <- workspace_path_remove(value[[key]], path[-1L])
  value
}

workspace_path_insert <- function(value, collection_path, position, item) {
  collection <- workspace_path_get(value, collection_path)
  if (!is.list(collection)) stop("Target parent is not a sequence.", call. = FALSE)
  item <- clone_metadata_value(item)
  if (length(collection) == 0L) {
    updated <- list(item)
  } else {
    position <- max(1L, min(as.integer(position), length(collection) + 1L))
    updated <- append(collection, list(item), after = position - 1L)
    names(updated) <- NULL
  }
  workspace_path_replace(value, collection_path, updated)
}

workspace_find_index <- function(collection, id) {
  if (!is.list(collection) || length(collection) == 0L) return(NA_integer_)
  ids <- vapply(collection, function(item) {
    if (is.list(item) && is.character(item$id) && length(item$id) == 1L) {
      item$id
    } else {
      NA_character_
    }
  }, character(1L))
  match(id, ids)
}

workspace_target_location <- function(bundle, target, allow_missing = FALSE) {
  target_error <- workspace_validate_target(target, allow_missing_id = allow_missing)
  if (!is.null(target_error)) return(list(error = target_error))
  kind <- target$document_type
  id <- target$document_id
  top_level <- c(population = "populations", header = "headers", table = "tables",
                 template = "templates")
  if (kind %in% names(top_level)) {
    collection_name <- unname(top_level[[kind]])
    collection <- bundle[[collection_name]]
    index <- workspace_find_index(collection, id)
    if (is.na(index)) {
      if (isTRUE(allow_missing)) {
        return(list(
          exists = FALSE,
          collection_path = list(collection_name),
          index = length(collection) + 1L,
          path = NULL,
          value = NULL
        ))
      }
      return(list(error = workspace_error(
        "workspace_target_missing",
        sprintf("Target %s '%s' is not present.", kind, id),
        paste0("$.", collection_name)
      )))
    }
    path <- list(collection_name, index)
    return(list(
      exists = TRUE, collection_path = list(collection_name), index = index,
      path = path, value = workspace_path_get(bundle, path)
    ))
  }

  template_id <- target$template_id
  if (is.null(template_id) || !is.character(template_id) || length(template_id) != 1L) {
    return(list(error = workspace_error(
      "workspace_target_invalid", "Nested target requires template_id.", "$.target.template_id"
    )))
  }
  template_index <- workspace_find_index(bundle$templates, template_id)
  if (is.na(template_index)) {
    return(list(error = workspace_error(
      "workspace_target_missing", sprintf("Template '%s' is not present.", template_id),
      "$.templates"
    )))
  }
  template_path <- list("templates", template_index)
  template <- workspace_path_get(bundle, template_path)
  if (is.null(template$body) || !is.list(template$body) ||
      is.null(template$body$chunks) || !is.list(template$body$chunks)) {
    return(list(error = workspace_error(
      "workspace_target_invalid", "Template body does not contain a chunk sequence.",
      paste0("$.templates[", template_index - 1L, "].body.chunks")
    )))
  }
  chunk_id <- target$chunk_id
  if (is.null(chunk_id) || !is.character(chunk_id) || length(chunk_id) != 1L) {
    return(list(error = workspace_error(
      "workspace_target_invalid", "Nested target requires chunk_id.", "$.target.chunk_id"
    )))
  }
  chunk_index <- workspace_find_index(template$body$chunks, chunk_id)
  if (is.na(chunk_index)) {
    return(list(error = workspace_error(
      "workspace_target_missing", sprintf("Chunk '%s' is not present.", chunk_id),
      paste0("$.templates[", template_index - 1L, "].body.chunks")
    )))
  }
  chunk_path <- c(template_path, list("body", "chunks", chunk_index))
  chunk <- workspace_path_get(bundle, chunk_path)

  if (identical(kind, "chunk")) {
    return(list(
      exists = TRUE, collection_path = list("templates", template_index, "body", "chunks"),
      index = chunk_index, path = chunk_path, value = chunk
    ))
  }

  if (identical(kind, "level") || identical(kind, "analysis_block")) {
    collection_name <- if (identical(kind, "level")) "levels" else "analysis_blocks"
    collection <- chunk[[collection_name]]
    if (!is.list(collection)) {
      return(list(error = workspace_error(
        "workspace_target_invalid", sprintf("Chunk does not contain a %s sequence.", collection_name),
        paste0("$.target.", collection_name)
      )))
    }
    nested_id <- if (identical(kind, "level")) target$level_id else target$analysis_id
    if (is.null(nested_id)) nested_id <- id
    nested_index <- workspace_find_index(collection, nested_id)
    if (is.na(nested_index)) {
      return(list(error = workspace_error(
        "workspace_target_missing", sprintf("Target %s '%s' is not present.", kind, nested_id),
        paste0("$.templates[", template_index - 1L, "].body.chunks[", chunk_index - 1L,
               "].", collection_name)
      )))
    }
    nested_path <- c(chunk_path, list(collection_name, nested_index))
    return(list(
      exists = TRUE,
      collection_path = c(chunk_path, list(collection_name)),
      index = nested_index, path = nested_path,
      value = workspace_path_get(bundle, nested_path)
    ))
  }

  if (identical(kind, "row")) {
    analysis_id <- target$analysis_id
    if (!is.null(analysis_id)) {
      block_index <- workspace_find_index(chunk$analysis_blocks, analysis_id)
      if (is.na(block_index)) {
        return(list(error = workspace_error(
          "workspace_target_missing", sprintf("Analysis block '%s' is not present.", analysis_id),
          paste0("$.templates[", template_index - 1L, "].body.chunks[", chunk_index - 1L,
                 "].analysis_blocks")
        )))
      }
      rows <- chunk$analysis_blocks[[block_index]]$rows
      collection_path <- c(chunk_path, list("analysis_blocks", block_index, "rows"))
    } else {
      block_index <- NULL
      rows <- chunk$rows
      collection_path <- c(chunk_path, list("rows"))
    }
    if (!is.list(rows)) {
      return(list(error = workspace_error(
        "workspace_target_invalid", "Row parent does not contain a row sequence.",
        "$.target.rows"
      )))
    }
    row_id <- target$row_id %||% id
    row_index <- workspace_find_index(rows, row_id)
    if (is.na(row_index)) {
      return(list(error = workspace_error(
        "workspace_target_missing", sprintf("Row '%s' is not present.", row_id),
        "$.target.row_id"
      )))
    }
    row_path <- c(collection_path, list(row_index))
    return(list(
      exists = TRUE, collection_path = collection_path, index = row_index,
      path = row_path, value = workspace_path_get(bundle, row_path),
      analysis_index = block_index
    ))
  }

  list(error = workspace_error(
    "workspace_target_invalid", sprintf("Target type '%s' is not supported.", kind),
    "$.target.document_type"
  ))
}

workspace_overlay_active_draft <- function(workspace) {
  bundle <- workspace_metadata_value(workspace)
  draft <- workspace$active_draft
  if (is.null(draft)) return(bundle)
  operation <- draft$operation %||% "update"
  if (identical(operation, "update") && !is.null(draft$path)) {
    return(workspace_path_replace(bundle, draft$path, draft$draft_value))
  }
  if (identical(operation, "create")) return(workspace_insert_draft(bundle, draft))
  if (identical(operation, "delete") && !is.null(draft$path)) {
    return(workspace_path_remove(bundle, draft$path))
  }
  bundle
}

workspace_target_parent_location <- function(bundle, target) {
  target_error <- workspace_validate_target(target, allow_missing_id = TRUE)
  if (!is.null(target_error)) return(list(error = target_error))
  kind <- target$document_type
  if (kind %in% c("population", "header", "table", "template")) {
    collection_name <- c(
      population = "populations", header = "headers", table = "tables", template = "templates"
    )[[kind]]
    return(list(collection_path = list(collection_name), position = Inf))
  }
  template_id <- target$template_id
  if (is.null(template_id)) {
    return(list(error = workspace_error(
      "workspace_target_invalid", "Nested target requires template_id.", "$.target.template_id"
    )))
  }
  ti <- workspace_find_index(bundle$templates, template_id)
  if (is.na(ti)) {
    return(list(error = workspace_error(
      "workspace_target_missing", sprintf("Template '%s' is not present.", template_id),
      "$.templates"
    )))
  }
  template_path <- list("templates", ti)
  if (identical(kind, "chunk")) {
    return(list(collection_path = c(template_path, list("body", "chunks")), position = Inf))
  }
  chunk_id <- target$chunk_id
  ci <- workspace_find_index(bundle$templates[[ti]]$body$chunks, chunk_id)
  if (is.na(ci)) {
    return(list(error = workspace_error(
      "workspace_target_missing", sprintf("Chunk '%s' is not present.", chunk_id),
      paste0("$.templates[", ti - 1L, "].body.chunks")
    )))
  }
  chunk_path <- c(template_path, list("body", "chunks", ci))
  collection_name <- switch(
    kind,
    level = "levels",
    analysis_block = "analysis_blocks",
    row = if (!is.null(target$analysis_id)) NULL else "rows",
    NULL
  )
  if (identical(kind, "row") && !is.null(target$analysis_id)) {
    ai <- workspace_find_index(bundle$templates[[ti]]$body$chunks[[ci]]$analysis_blocks,
                               target$analysis_id)
    if (is.na(ai)) {
      return(list(error = workspace_error(
        "workspace_target_missing", sprintf("Analysis block '%s' is not present.", target$analysis_id),
        "$.target.analysis_id"
      )))
    }
    collection_path <- c(chunk_path, list("analysis_blocks", ai, "rows"))
    collection <- workspace_path_get(bundle, collection_path)
    if (!is.list(collection)) {
      return(list(error = workspace_error(
        "workspace_target_invalid", "Analysis block does not contain a row sequence.",
        "$.target.rows"
      )))
    }
    return(list(collection_path = collection_path, position = Inf))
  }
  if (is.null(collection_name)) {
    return(list(error = workspace_error(
      "workspace_target_invalid", sprintf("Target type '%s' cannot be inserted here.", kind),
      "$.target.document_type"
    )))
  }
  collection_path <- c(chunk_path, list(collection_name))
  collection <- workspace_path_get(bundle, collection_path)
  if (!is.list(collection)) {
    return(list(error = workspace_error(
      "workspace_target_invalid",
      sprintf("Chunk does not contain a %s sequence.", collection_name),
      paste0("$.target.", collection_name)
    )))
  }
  list(collection_path = collection_path, position = Inf)
}

workspace_remap_error_stage <- function(errors, stage = "workspace") {
  lapply(errors, function(item) {
    new_error_item(stage, item$code, item$message, item$path)
  })
}

workspace_reindex_bundle_positions <- function(bundle) {
  result <- clone_metadata_value(bundle)
  for (template_index in seq_along(result$templates)) {
    template <- result$templates[[template_index]]
    if (is.null(template$body) || !is.list(template$body) ||
        !is.list(template$body$chunks)) next
    chunks <- template$body$chunks
    for (chunk_index in seq_along(chunks)) {
      chunk <- chunks[[chunk_index]]
      old_chunk_id <- chunk$id
      new_chunk_id <- sprintf("%s_%03d", template$id, chunk_index)
      chunk$id <- new_chunk_id
      if (identical(chunk$type, "hierarchical_summary")) {
        levels <- chunk$levels
        level_map <- character()
        if (is.list(levels)) {
          old_ids <- vapply(levels, `[[`, character(1L), "id")
          new_ids <- sprintf("%s_level_%03d", new_chunk_id, seq_along(levels))
          level_map <- stats::setNames(new_ids, old_ids)
          for (i in seq_along(levels)) levels[[i]]$id <- new_ids[[i]]
        }
        blocks <- chunk$analysis_blocks
        block_map <- character()
        row_maps <- list()
        if (is.list(blocks)) {
          old_block_ids <- vapply(blocks, `[[`, character(1L), "id")
          new_block_ids <- sprintf("%s_analysis_%03d", new_chunk_id, seq_along(blocks))
          block_map <- stats::setNames(new_block_ids, old_block_ids)
          for (i in seq_along(blocks)) {
            block <- blocks[[i]]
            old_row_ids <- if (is.list(block$rows) && length(block$rows) > 0L) {
              vapply(block$rows, `[[`, character(1L), "id")
            } else character()
            new_row_ids <- sprintf("%s_%03d", new_block_ids[[i]], seq_along(old_row_ids))
            row_maps[[old_block_ids[[i]]]] <- stats::setNames(new_row_ids, old_row_ids)
            block$id <- new_block_ids[[i]]
            if (length(old_row_ids) > 0L) {
              for (j in seq_along(block$rows)) block$rows[[j]]$id <- new_row_ids[[j]]
            }
            if (!is.null(block$anchor_level) && block$anchor_level %in% names(level_map)) {
              block$anchor_level <- unname(level_map[[block$anchor_level]])
            }
            blocks[[i]] <- block
          }
          for (i in seq_along(levels)) {
            level <- levels[[i]]
            if (!is.null(level$node_analysis_id) && level$node_analysis_id %in% names(block_map)) {
              level$node_analysis_id <- unname(block_map[[level$node_analysis_id]])
            }
            if (!is.null(level$result_sort)) {
              metric <- level$result_sort$metric
              old_analysis <- metric$analysis_id
              if (!is.null(old_analysis) && old_analysis %in% names(block_map)) {
                metric$analysis_id <- unname(block_map[[old_analysis]])
                row_map <- row_maps[[old_analysis]]
                if (!is.null(row_map) && !is.null(metric$row_id) &&
                    metric$row_id %in% names(row_map)) {
                  metric$row_id <- unname(row_map[[metric$row_id]])
                }
                level$result_sort$metric <- metric
              }
            }
            levels[[i]] <- level
          }
        }
        chunk$levels <- levels
        chunk$analysis_blocks <- blocks
      } else if (is.list(chunk$rows)) {
        new_row_ids <- sprintf("%s_%03d", new_chunk_id, seq_along(chunk$rows))
        for (row_index in seq_along(chunk$rows)) chunk$rows[[row_index]]$id <- new_row_ids[[row_index]]
      }
      chunks[[chunk_index]] <- chunk
      invisible(old_chunk_id)
    }
    template$body$chunks <- chunks
    result$templates[[template_index]] <- template
  }
  result
}

workspace_position_id <- function(bundle, target, position = Inf) {
  kind <- target$document_type
  position <- if (is.finite(position)) as.integer(position) else 1L
  if (kind %in% c("population", "header", "table", "template")) return(NULL)
  template_id <- target$template_id
  if (identical(kind, "chunk")) {
    return(sprintf("%s_%03d", template_id, position))
  }
  chunk_id <- target$chunk_id
  if (identical(kind, "level")) return(sprintf("%s_level_%03d", chunk_id, position))
  if (identical(kind, "analysis_block")) {
    return(sprintf("%s_analysis_%03d", chunk_id, position))
  }
  if (identical(kind, "row")) {
    parent <- target$analysis_id
    if (is.null(parent)) parent <- chunk_id
    return(sprintf("%s_%03d", parent, position))
  }
  NULL
}

workspace_insert_draft <- function(bundle, draft) {
  parent <- workspace_path_get(bundle, draft$parent_path)
  position <- draft$position
  if (!is.finite(position)) position <- length(parent) + 1L
  item <- clone_metadata_value(draft$draft_value)
  if (is.null(item$id) || !is.character(item$id) || length(item$id) != 1L ||
      !nzchar(item$id)) {
    item$id <- workspace_position_id(bundle, draft$target, position)
  }
  workspace_path_insert(bundle, draft$parent_path, position, item)
}

workspace_apply_draft_value <- function(workspace, registry = default_chunk_registry()) {
  draft <- workspace$active_draft
  bundle <- workspace_metadata_value(workspace)
  operation <- draft$operation %||% "update"
  if (identical(operation, "update")) {
    location <- workspace_target_location(bundle, draft$target)
    if (!is.null(location$error)) return(list(errors = list(location$error)))
    if (is.list(draft$base_value) && is.list(draft$draft_value) &&
        !is.null(draft$base_value$id) && !is.null(draft$draft_value$id) &&
        !identical(draft$base_value$id, draft$draft_value$id)) {
      return(list(errors = list(workspace_error(
        "workspace_id_immutable", "Position and object IDs cannot be edited directly.",
        "$.active_draft.draft_value.id"
      ))))
    }
    candidate <- workspace_path_replace(bundle, location$path, draft$draft_value)
  } else if (identical(operation, "create")) {
    candidate <- workspace_insert_draft(bundle, draft)
  } else if (identical(operation, "delete")) {
    candidate <- workspace_path_remove(bundle, draft$path)
  } else {
    return(list(errors = list(workspace_error(
      "workspace_draft_invalid", "Draft operation is invalid.", "$.active_draft.operation"
    ))))
  }

  first_validation <- parse_bundle_value(candidate, registry)
  if (length(first_validation$errors) > 0L) {
    return(list(errors = workspace_remap_error_stage(first_validation$errors)))
  }
  normalized <- if (isTRUE(draft$reindex_positions)) {
    workspace_reindex_bundle_positions(first_validation$value)
  } else {
    first_validation$value
  }
  second_validation <- parse_bundle_value(normalized, registry)
  if (length(second_validation$errors) > 0L) {
    return(list(errors = workspace_remap_error_stage(second_validation$errors)))
  }
  list(value = second_validation$value, errors = list())
}

workspace_begin_draft <- function(workspace, document_type, document_id = NULL,
                                  template_id = NULL, chunk_id = NULL,
                                  level_id = NULL, analysis_id = NULL,
                                  row_id = NULL, parent_id = NULL,
                                  operation = c("update", "create"), value = NULL,
                                  position = Inf) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  operation <- match.arg(operation)
  target <- workspace_target(document_type, document_id, template_id, chunk_id,
                             level_id, analysis_id, row_id, parent_id)
  target_error <- workspace_validate_target(target, allow_missing_id = identical(operation, "create"))
  if (!is.null(target_error)) return(workspace_error_result(workspace, list(target_error)))
  if (identical(operation, "create")) {
    position_error <- workspace_validate_position(position, allow_infinite = TRUE)
    if (!is.null(position_error)) return(workspace_error_result(workspace, list(position_error)))
  }
  conflict <- workspace_active_draft_conflict(workspace, target, operation)
  if (!is.null(conflict)) return(workspace_error_result(workspace, list(conflict)))
  if (!is.null(workspace$active_draft) &&
      identical(workspace$active_draft$operation, operation) &&
      workspace_same_target(workspace$active_draft$target, target)) {
    if (identical(operation, "update") && !is.null(value)) {
      return(workspace_set_draft(workspace, value))
    }
    return(workspace_ok_result(
      workspace, value = workspace_draft_value(workspace), changed = FALSE
    ))
  }
  bundle <- workspace_metadata_value(workspace)
  if (identical(operation, "update")) {
    location <- workspace_target_location(bundle, target)
    if (!is.null(location$error)) return(workspace_error_result(workspace, list(location$error)))
    base_value <- clone_metadata_value(location$value)
    draft_value <- if (is.null(value)) clone_metadata_value(base_value) else clone_metadata_value(value)
    draft <- list(
      operation = "update", target = target, path = location$path,
      parent_path = location$collection_path, position = location$index,
      document_type = target$document_type, document_id = target$document_id,
      base_value = base_value, draft_value = draft_value,
      dirty = !identical(base_value, draft_value),
      reindex_positions = target$document_type %in%
        c("template", "chunk", "level", "analysis_block", "row"),
      draft_base_revision = workspace$revision$saved_revision
    )
  } else {
    parent <- workspace_target_parent_location(bundle, target)
    if (!is.null(parent$error)) return(workspace_error_result(workspace, list(parent$error)))
    if (is.null(value) || !is.list(value)) {
      return(workspace_error_result(workspace, list(workspace_error(
        "workspace_draft_invalid", "A list value is required for a create draft.",
        "$.active_draft.draft_value"
      ))))
    }
    draft <- list(
      operation = "create", target = target, path = NULL,
      parent_path = parent$collection_path,
      position = if (is.finite(position)) as.integer(position) else parent$position,
      document_type = target$document_type,
      document_id = target$document_id %||% value$id,
      base_value = NULL, draft_value = clone_metadata_value(value), dirty = TRUE,
      reindex_positions = target$document_type %in%
        c("template", "chunk", "level", "analysis_block", "row"),
      draft_base_revision = workspace$revision$saved_revision
    )
  }
  revision <- workspace$revision
  revision$draft_base_revision <- revision$saved_revision
  next_workspace <- workspace_with_metadata(
    workspace, bundle, active_draft = draft,
    parse_diagnostic = workspace$parse_diagnostic,
    revision = revision
  )
  workspace_ok_result(next_workspace, value = workspace_draft_value(next_workspace), changed = draft$dirty)
}

workspace_set_draft <- function(workspace, value) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  if (is.null(workspace$active_draft)) {
    return(workspace_error_result(workspace, list(workspace_error(
      "workspace_draft_missing", "There is no active draft.", "$.active_draft"
    ))))
  }
  draft <- clone_metadata_value(workspace$active_draft)
  draft$draft_value <- clone_metadata_value(value)
  if (identical(draft$operation, "create")) {
    draft$dirty <- TRUE
  } else {
    draft$dirty <- !identical(draft$base_value, draft$draft_value)
  }
  next_workspace <- workspace_with_metadata(
    workspace, workspace_metadata_value(workspace), active_draft = draft,
    parse_diagnostic = workspace$parse_diagnostic, revision = workspace$revision
  )
  workspace_ok_result(next_workspace, value = clone_metadata_value(value), changed = draft$dirty)
}

workspace_update_draft <- workspace_set_draft

workspace_discard_draft <- function(workspace) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  revision <- workspace$revision
  revision$draft_base_revision <- NULL
  next_workspace <- workspace_with_metadata(
    workspace, workspace_metadata_value(workspace), active_draft = NULL,
    parse_diagnostic = workspace$parse_diagnostic, revision = revision
  )
  workspace_ok_result(next_workspace, changed = !is.null(workspace$active_draft))
}

workspace_cancel <- function(workspace) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  workspace_ok_result(workspace, changed = FALSE)
}

workspace_save_draft <- function(workspace, registry = default_chunk_registry()) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  if (is.null(workspace$active_draft)) return(workspace_ok_result(workspace, changed = FALSE))
  draft <- workspace$active_draft
  if (!isTRUE(draft$dirty)) {
    return(workspace_ok_result(
      workspace_discard_draft(workspace)$workspace, changed = FALSE
    ))
  }
  if (identical(draft$operation, "delete")) {
    impact <- workspace_delete_impact(
      workspace, draft$target$document_type, draft$target$document_id,
      template_id = draft$target$template_id, chunk_id = draft$target$chunk_id,
      level_id = draft$target$level_id, analysis_id = draft$target$analysis_id,
      row_id = draft$target$row_id
    )
    if (!isTRUE(impact$allowed) || !isTRUE(draft$confirmed)) {
      errors <- impact$errors
      if (length(errors) == 0L) {
        errors <- list(workspace_error(
          "workspace_delete_confirmation_required", "Delete confirmation is required.",
          "$.active_draft"
        ))
      }
      return(workspace_error_result(workspace, errors))
    }
  }
  applied <- workspace_apply_draft_value(workspace, registry)
  if (length(applied$errors) > 0L) return(workspace_error_result(workspace, applied$errors))
  revision <- workspace$revision
  revision$saved_revision <- as.integer(revision$saved_revision + 1L)
  revision$draft_base_revision <- NULL
  next_workspace <- workspace_with_metadata(
    workspace, applied$value, active_draft = NULL,
    parse_diagnostic = workspace$parse_diagnostic, revision = revision
  )
  workspace_ok_result(next_workspace, value = workspace_saved_snapshot(next_workspace), changed = TRUE)
}

workspace_import_bundle <- function(workspace, input,
                                     registry = default_chunk_registry(),
                                     allow_dirty = FALSE) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  if (workspace_is_dirty(workspace) && !isTRUE(allow_dirty)) {
    return(workspace_error_result(workspace, list(workspace_error(
      "workspace_draft_dirty",
      "Import is blocked while the active draft contains unsaved changes.",
      "$.active_draft"
    ))))
  }
  imported <- parse_bundle_archive(input, registry)
  if (!isTRUE(imported$passed)) {
    next_workspace <- workspace_with_metadata(
      workspace, workspace_metadata_value(workspace),
      active_draft = workspace$active_draft,
      parse_diagnostic = imported$errors, revision = workspace$revision
    )
    return(workspace_error_result(next_workspace, imported$errors))
  }
  revision <- workspace$revision
  revision$saved_revision <- as.integer(revision$saved_revision + 1L)
  revision$draft_base_revision <- NULL
  next_workspace <- workspace_with_metadata(
    workspace, imported$workspace, active_draft = NULL,
    parse_diagnostic = list(), revision = revision
  )
  workspace_ok_result(next_workspace, value = workspace_saved_snapshot(next_workspace), changed = TRUE)
}

workspace_import <- workspace_import_bundle

workspace_export_bundle <- function(workspace, registry = default_chunk_registry()) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  encoded <- tryCatch(
    canonical_archive_bytes(workspace_saved_snapshot(workspace), registry),
    error = function(error) error
  )
  if (inherits(encoded, "error")) {
    return(workspace_error_result(workspace, list(workspace_error(
      "workspace_export_invalid", "Saved metadata cannot be encoded.", "$"
    ))))
  }
  workspace_ok_result(workspace, value = encoded, changed = FALSE)
}

workspace_export_bytes <- function(workspace, registry = default_chunk_registry()) {
  result <- workspace_export_bundle(workspace, registry)
  if (!isTRUE(result$passed)) stop("Saved metadata cannot be encoded.", call. = FALSE)
  result$value
}

workspace_record_import_failure <- function(workspace, errors) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  if (!is.list(errors)) stop("errors must be a list of ErrorItem values.", call. = FALSE)
  next_workspace <- workspace_with_metadata(
    workspace, workspace_metadata_value(workspace), workspace$active_draft,
    parse_diagnostic = errors, revision = workspace$revision
  )
  workspace_ok_result(next_workspace, value = errors, changed = !identical(errors, workspace$parse_diagnostic))
}

workspace_delete_impact <- function(workspace, document_type, document_id = NULL,
                                    template_id = NULL, chunk_id = NULL,
                                    level_id = NULL, analysis_id = NULL,
                                    row_id = NULL) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  target <- workspace_target(document_type, document_id, template_id, chunk_id,
                             level_id, analysis_id, row_id)
  target_error <- workspace_validate_target(target)
  if (!is.null(target_error)) {
    return(list(
      allowed = FALSE, requires_confirmation = FALSE, target = target,
      affected_tables = character(), effects = character(), errors = list(target_error)
    ))
  }
  bundle <- workspace_metadata_value(workspace)
  location <- workspace_target_location(bundle, target)
  if (!is.null(location$error)) {
    return(list(
      allowed = FALSE, requires_confirmation = FALSE, target = target,
      affected_tables = character(), effects = character(), errors = list(location$error)
    ))
  }
  affected_tables <- character()
  if (target$document_type %in% c("population", "header", "template")) {
    field <- c(population = "population_id", header = "header_id", template = "template_id")[[target$document_type]]
    affected_tables <- vapply(bundle$tables, function(table) {
      if (identical(table[[field]], target$document_id)) table$id else NA_character_
    }, character(1L))
    affected_tables <- affected_tables[!is.na(affected_tables)]
  }
  allowed <- length(affected_tables) == 0L
  effects <- if (allowed) {
    "The target will be removed and position IDs will be rebuilt where applicable."
  } else {
    "The target is referenced by a table and cannot be removed."
  }
  list(
    operation = "delete", target = target, affected_tables = affected_tables,
    effects = effects, requires_confirmation = TRUE, allowed = allowed,
    errors = if (allowed) list() else list(workspace_error(
      "workspace_delete_referenced",
      sprintf("Target '%s' is referenced by a table.", target$document_id),
      "$.target.document_id"
    ))
  )
}

workspace_begin_delete <- function(workspace, document_type, document_id = NULL,
                                   template_id = NULL, chunk_id = NULL,
                                   level_id = NULL, analysis_id = NULL,
                                   row_id = NULL, confirm = FALSE) {
  impact <- workspace_delete_impact(
    workspace, document_type, document_id, template_id, chunk_id,
    level_id, analysis_id, row_id
  )
  if (length(impact$errors) > 0L && !isTRUE(impact$allowed)) {
    return(workspace_error_result(workspace, impact$errors, value = impact))
  }
  target <- impact$target
  conflict <- workspace_active_draft_conflict(workspace, target, "delete")
  if (!is.null(conflict)) return(workspace_error_result(workspace, list(conflict), value = impact))
  if (!is.null(workspace$active_draft) &&
      identical(workspace$active_draft$operation, "delete") &&
      workspace_same_target(workspace$active_draft$target, target)) {
    if (isTRUE(confirm)) {
      return(workspace_confirm_delete(workspace))
    }
    return(workspace_ok_result(workspace, value = impact, changed = FALSE))
  }
  location <- workspace_target_location(workspace_metadata_value(workspace), target)
  draft <- list(
    operation = "delete", target = target, path = location$path,
    parent_path = location$collection_path, position = location$index,
    document_type = target$document_type, document_id = target$document_id,
    base_value = clone_metadata_value(location$value), draft_value = NULL,
    dirty = TRUE, confirmed = isTRUE(confirm),
    reindex_positions = target$document_type %in%
      c("template", "chunk", "level", "analysis_block", "row"),
    draft_base_revision = workspace$revision$saved_revision
  )
  revision <- workspace$revision
  revision$draft_base_revision <- revision$saved_revision
  next_workspace <- workspace_with_metadata(
    workspace, workspace_metadata_value(workspace), draft,
    parse_diagnostic = workspace$parse_diagnostic, revision = revision
  )
  workspace_ok_result(next_workspace, value = impact, changed = TRUE)
}

workspace_confirm_delete <- function(workspace) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  if (is.null(workspace$active_draft) || !identical(workspace$active_draft$operation, "delete")) {
    return(workspace_error_result(workspace, list(workspace_error(
      "workspace_draft_invalid", "There is no pending delete draft.", "$.active_draft"
    ))))
  }
  draft <- workspace$active_draft
  draft$confirmed <- TRUE
  next_workspace <- workspace_with_metadata(
    workspace, workspace_metadata_value(workspace), draft,
    parse_diagnostic = workspace$parse_diagnostic, revision = workspace$revision
  )
  workspace_ok_result(next_workspace, changed = TRUE)
}

workspace_move_collection_item <- function(bundle, collection_path, index, new_index) {
  collection <- workspace_path_get(bundle, collection_path)
  if (!is.list(collection) || length(collection) == 0L) return(bundle)
  index <- as.integer(index)
  new_index <- max(1L, min(as.integer(new_index), length(collection)))
  if (index == new_index) return(bundle)
  item <- collection[[index]]
  collection <- collection[-index]
  collection <- append(collection, list(item), after = new_index - 1L)
  names(collection) <- NULL
  workspace_path_replace(bundle, collection_path, collection)
}

workspace_move_draft <- function(workspace, document_type, document_id = NULL,
                                 template_id = NULL, chunk_id = NULL,
                                 level_id = NULL, analysis_id = NULL,
                                 row_id = NULL, direction = c("up", "down"),
                                 position = NULL) {
  if (!is_workspace(workspace)) stop("workspace must be a MetadataWorkspace.", call. = FALSE)
  direction <- match.arg(direction)
  target <- workspace_target(document_type, document_id, template_id, chunk_id,
                             level_id, analysis_id, row_id)
  if (!target$document_type %in% c("chunk", "level", "analysis_block", "row")) {
    return(workspace_error_result(workspace, list(workspace_error(
      "workspace_target_invalid",
      "Only nested template sequences support move operations.",
      "$.target.document_type"
    ))))
  }
  if (!is.null(position)) {
    position_error <- workspace_validate_position(
      position, allow_infinite = FALSE, path = "$.position"
    )
    if (!is.null(position_error)) return(workspace_error_result(workspace, list(position_error)))
  }
  parent_target <- workspace_target("template", target$template_id)
  begun <- workspace_begin_draft(
    workspace, parent_target$document_type, parent_target$document_id,
    parent_target$template_id, parent_target$chunk_id, parent_target$level_id,
    parent_target$analysis_id, parent_target$row_id, operation = "update"
  )
  if (!isTRUE(begun$passed)) return(begun)
  draft_workspace <- begun$workspace
  # Resolve the corresponding path inside the template draft by using its IDs.
  draft_bundle <- workspace_overlay_active_draft(draft_workspace)
  current_location <- workspace_target_location(draft_bundle, target)
  if (!is.null(current_location$error)) {
    return(workspace_error_result(workspace, list(current_location$error)))
  }
  collection <- workspace_path_get(draft_bundle, current_location$collection_path)
  desired <- if (!is.null(position)) as.integer(position) else {
    if (identical(direction, "up")) current_location$index - 1L else current_location$index + 1L
  }
  desired <- max(1L, min(desired, length(collection)))
  moved_bundle <- workspace_move_collection_item(
    draft_bundle, current_location$collection_path, current_location$index, desired
  )
  template_location <- workspace_target_location(moved_bundle, parent_target)
  if (!is.null(template_location$error)) {
    return(workspace_error_result(workspace, list(template_location$error)))
  }
  set_result <- workspace_set_draft(draft_workspace, template_location$value)
  if (!isTRUE(set_result$passed)) return(set_result)
  set_result
}

workspace_create <- function(workspace, document_type, value,
                             template_id = NULL, chunk_id = NULL,
                             analysis_id = NULL, position = Inf,
                             registry = default_chunk_registry()) {
  begun <- workspace_begin_draft(
    workspace, document_type, document_id = value$id %||% NULL,
    template_id = template_id, chunk_id = chunk_id, analysis_id = analysis_id,
    operation = "create", value = value, position = position
  )
  if (!isTRUE(begun$passed)) return(begun)
  workspace_save_draft(begun$workspace, registry)
}

workspace_update <- function(workspace, target, value,
                             registry = default_chunk_registry()) {
  target <- workspace_target(target)
  begun <- workspace_begin_draft(workspace, target, operation = "update")
  if (!isTRUE(begun$passed)) return(begun)
  updated <- workspace_set_draft(begun$workspace, value)
  if (!isTRUE(updated$passed)) return(updated)
  workspace_save_draft(updated$workspace, registry)
}

workspace_delete <- function(workspace, target, confirm = FALSE,
                             registry = default_chunk_registry()) {
  target <- workspace_target(target)
  begun <- workspace_begin_delete(
    workspace, target$document_type, target$document_id,
    target$template_id, target$chunk_id, target$level_id,
    target$analysis_id, target$row_id, confirm = confirm
  )
  if (!isTRUE(begun$passed)) return(begun)
  workspace_save_draft(begun$workspace, registry)
}

workspace_move <- function(workspace, target, direction = c("up", "down"),
                           position = NULL, registry = default_chunk_registry()) {
  target <- workspace_target(target)
  moved <- workspace_move_draft(
    workspace, target$document_type, target$document_id,
    target$template_id, target$chunk_id, target$level_id,
    target$analysis_id, target$row_id, direction, position
  )
  if (!isTRUE(moved$passed)) return(moved)
  workspace_save_draft(moved$workspace, registry)
}

print.MetadataWorkspace <- function(x, ...) {
  cat(sprintf(
    "MetadataWorkspace(saved_revision = %s, dirty = %s)\n",
    x$revision$saved_revision, if (workspace_is_dirty(x)) "TRUE" else "FALSE"
  ))
  invisible(x)
}

print.WorkspaceResult <- function(x, ...) {
  cat(sprintf(
    "WorkspaceResult(passed = %s, changed = %s, errors = %d)\n",
    if (x$passed) "TRUE" else "FALSE", if (x$changed) "TRUE" else "FALSE",
    length(x$errors)
  ))
  invisible(x)
}
