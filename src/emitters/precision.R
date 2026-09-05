# Host-side relative precision contract used by emitters and tests.

resolve_relative_digits <- function(base_digits, digits) {
  if (!is.numeric(base_digits) || length(base_digits) != 1L ||
      is.na(base_digits) || base_digits < 0 || base_digits != as.integer(base_digits)) {
    stop("Base digits must be a non-negative integer.", call. = FALSE)
  }
  if (is.null(digits)) return(as.integer(base_digits))
  if (is.numeric(digits) && length(digits) == 1L && !is.na(digits) &&
      digits >= 0 && digits == as.integer(digits)) {
    return(as.integer(digits))
  }
  if (is.character(digits) && length(digits) == 1L && grepl("^[+-][0-9]+$", digits)) {
    offset <- as.integer(sub("^.", "", digits))
    if (startsWith(digits, "-")) offset <- -offset
    resolved <- as.integer(base_digits + offset)
    if (resolved < 0L) stop("Relative digits resolve to a negative value.", call. = FALSE)
    return(resolved)
  }
  stop("Digits must be a non-negative integer or signed relative value.", call. = FALSE)
}
