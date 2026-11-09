# Host-side relative precision contract used by emitters and tests.

# as.integer() is a range-gated conversion: above .Machine$integer.max it returns NA
# with a coercion warning. Comparing against NA then yields NA, and `if (NA)` is an
# error rather than a false branch, so an out-of-range value used to escape as
# "missing value where TRUE/FALSE needed" instead of naming digits. Bound the value
# before converting so the failure is the caller's message.
representable_integer <- function(value) {
  is.numeric(value) && length(value) == 1L && !is.na(value) && is.finite(value) &&
    value == trunc(value) && abs(value) <= .Machine$integer.max
}

resolve_relative_digits <- function(base_digits, digits) {
  if (!representable_integer(base_digits) || base_digits < 0) {
    stop("Base digits must be a non-negative integer.", call. = FALSE)
  }
  if (is.null(digits)) return(as.integer(base_digits))
  if (representable_integer(digits) && digits >= 0) {
    return(as.integer(digits))
  }
  if (is.character(digits) && length(digits) == 1L && grepl("^[+-][0-9]+$", digits)) {
    offset <- as.integer(sub("^.", "", digits))
    if (startsWith(digits, "-")) offset <- -offset
    resolved <- as.integer(base_digits + offset)
    if (resolved < 0L) stop("Relative digits resolve to a negative value.", call. = FALSE)
    return(resolved)
  }
  stop("Field 'digits' must be a non-negative integer or a signed relative value ",
       "within the integer range.", call. = FALSE)
}
