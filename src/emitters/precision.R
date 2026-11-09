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
    # The relative offset is parsed from text, so it can be arbitrarily long even
    # though a digits count cannot. Convert through double first and bound it: a
    # direct as.integer() on "+99999999999" warns and yields NA, which then makes
    # the comparison below an error instead of a message.
    offset <- as.numeric(sub("^.", "", digits))
    if (startsWith(digits, "-")) offset <- -offset
    if (!representable_integer(offset)) {
      stop("Field 'digits' relative offset must be within the integer range.",
           call. = FALSE)
    }
    resolved <- base_digits + offset
    if (!representable_integer(resolved)) {
      stop("Field 'digits' relative offset resolves outside the integer range.",
           call. = FALSE)
    }
    if (resolved < 0) stop("Relative digits resolve to a negative value.", call. = FALSE)
    return(as.integer(resolved))
  }
  stop("Field 'digits' must be a non-negative integer or a signed relative value ",
       "within the integer range.", call. = FALSE)
}
