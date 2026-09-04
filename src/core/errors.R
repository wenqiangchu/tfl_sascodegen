# Stable error and value-object helpers shared by the core modules.

new_error_item <- function(stage, code, message, path = "$") {
  stopifnot(is.character(stage), length(stage) == 1L)
  stopifnot(is.character(code), length(code) == 1L)
  stopifnot(is.character(message), length(message) == 1L)
  stopifnot(is.character(path), length(path) == 1L)
  structure(
    list(stage = stage, code = code, message = message, path = path),
    class = c("ErrorItem", "list")
  )
}

error_item_list <- function(item) {
  unclass(item)
}

new_error_collector <- function() {
  e <- new.env(parent = emptyenv())
  e$items <- list()
  e
}

add_error <- function(collector, stage, code, message, path = "$") {
  collector$items[[length(collector$items) + 1L]] <-
    new_error_item(stage, code, message, path)
  invisible(NULL)
}

error_items <- function(collector) {
  collector$items
}

error_path_field <- function(path, field) {
  if (identical(path, "$") || identical(path, "")) {
    paste0("$.", field)
  } else {
    paste0(path, ".", field)
  }
}

error_path_index <- function(path, index) {
  paste0(path, "[", as.integer(index), "]")
}

new_bundle_import_result <- function(passed, workspace = NULL, errors = list()) {
  stopifnot(is.logical(passed), length(passed) == 1L)
  structure(
    list(
      passed = isTRUE(passed),
      workspace = if (isTRUE(passed)) workspace else NULL,
      errors = errors
    ),
    class = c("BundleImportResult", "list")
  )
}

new_canonical_bytes <- function(bytes) {
  if (is.character(bytes) && length(bytes) == 1L) {
    bytes <- charToRaw(enc2utf8(bytes))
  }
  if (!is.raw(bytes)) {
    stop("Canonical bytes must be a raw vector.", call. = FALSE)
  }
  structure(list(bytes = bytes), class = c("CanonicalBytes", "list"))
}

as.raw.CanonicalBytes <- function(x, ...) {
  x$bytes
}

as.character.CanonicalBytes <- function(x, ...) {
  rawToChar(x$bytes)
}

length.CanonicalBytes <- function(x) {
  length(x$bytes)
}

print.ErrorItem <- function(x, ...) {
  cat(sprintf("%s: %s (%s) [%s]\n", x$stage, x$message, x$code, x$path))
  invisible(x)
}

print.BundleImportResult <- function(x, ...) {
  cat(sprintf("BundleImportResult(passed = %s, errors = %d)\n",
              if (x$passed) "TRUE" else "FALSE", length(x$errors)))
  invisible(x)
}
