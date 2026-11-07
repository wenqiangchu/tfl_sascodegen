# Guards the dummy study shell documents.
#
# The shells are hand-written specifications, so they drift: a missing section, a
# variable that no longer exists, or a value copied from memory. The deeper
# cross-check (declared char(N) against SAS lengths) lives in
# dummy_study/tools/check_shells.py; this file keeps the structural guarantees
# inside the normal R suite.

shell_dir <- file.path(project_root, "dummy_study", "shell")
expected_shells <- c(
  "14.1.1-disposition.md",
  "14.1.2-baseline-characteristics.md",
  "14.2.3-hgb-shift.md",
  "14.3.1.2-teae-by-soc-pt.md",
  "14.3.1.4-teae-by-soc-pt-severity.md",
  "14.3.1.5-serious-teae-by-soc-pt.md",
  "14.3.2.1-hgb-by-visit.md"
)
sections <- c("## 1. Identity", "## 2. Columns", "## 3. Rows",
              "## 4. Variable dictionary", "## 5. Chunk plan", "## 6. Open points")

testthat::test_that("the dummy study ships the planned set of shells", {
  files <- sort(list.files(shell_dir, pattern = "\\.md$"))
  testthat::expect_identical(files, sort(expected_shells))
})

testthat::test_that("every shell carries all six template sections in order", {
  for (name in expected_shells) {
    text <- readLines(file.path(shell_dir, name), warn = FALSE)
    positions <- vapply(sections, function(section) {
      hit <- which(startsWith(text, section))
      if (length(hit) == 0L) NA_integer_ else hit[[1L]]
    }, integer(1L))
    testthat::expect_false(any(is.na(positions)), label = paste(name, "missing section"))
    testthat::expect_true(all(diff(positions) > 0L), label = paste(name, "section order"))
  }
})

testthat::test_that("shells do not present a missing value as the string nan", {
  for (name in expected_shells) {
    text <- paste(readLines(file.path(shell_dir, name), warn = FALSE), collapse = "\n")
    testthat::expect_false(grepl("`nan`", text, fixed = TRUE),
                           label = paste(name, "literal nan"))
  }
})

testthat::test_that("shell variable references use a known dataset prefix", {
  known <- c("ADSL", "ADAE", "ADLBH", "WORK")
  for (name in expected_shells) {
    text <- paste(readLines(file.path(shell_dir, name), warn = FALSE), collapse = "\n")
    refs <- regmatches(text, gregexpr("`[A-Z]+\\.[A-Z0-9_]+`", text))[[1L]]
    domains <- unique(sub("`([A-Z]+)\\..*", "\\1", refs))
    unknown <- setdiff(domains, known)
    testthat::expect_true(length(unknown) == 0L,
                          label = paste(name, "unknown domains:", paste(unknown, collapse = ", ")))
  }
})

# A section heading is not a statistic, so no numeric check can notice it going
# missing; the first draft of the bundle dropped all seven of them from 14.1.2
# while every cell still matched. This ties the shells' declared label rows to
# the rows the templates actually emit.
testthat::test_that("every declared section label row is emitted by its template", {
  shell_dir <- file.path(project_root, "dummy_study", "shell")
  table_dir <- file.path(project_root, "dummy_study", "metadata", "tables")
  template_dir <- file.path(project_root, "dummy_study", "metadata", "templates")

  is_label_row <- function(line) {
    if (!startsWith(line, "|")) return(FALSE)
    # Splitting on the pipes leaves an empty cell on each side of the row.
    cells <- trimws(gsub("*", "", strsplit(line, "|", fixed = TRUE)[[1L]], fixed = TRUE))
    cells <- cells[nzchar(cells)]
    if (length(cells) == 0L) return(FALSE)
    if (!grepl("^[0-9]+$", cells[[1L]])) return(FALSE)
    "label" %in% tolower(cells)
  }

  count_label_rows <- function(lines) sum(vapply(lines, is_label_row, logical(1L)))

  count_template_label_rows <- function(lines) {
    if (length(lines) < 2L) return(0L)
    sum(vapply(seq_len(length(lines) - 1L), function(i) {
      grepl("- id:", lines[[i]], fixed = TRUE) &&
        grepl("type: 'label'", lines[[i + 1L]], fixed = TRUE)
    }, logical(1L)))
  }

  sheets <- list.files(shell_dir, pattern = "[.]md$", full.names = TRUE)
  testthat::expect_gt(length(sheets), 0L)
  for (sheet in sheets) {
    number <- sub("^(([0-9]+[.])+[0-9]+).*$", "\\1", basename(sheet))
    prefix <- paste0("^t_", gsub(".", "_", number, fixed = TRUE), "_.*[.]yaml$")
    candidates <- list.files(table_dir, pattern = prefix, full.names = TRUE)
    testthat::expect_length(candidates, 1L)

    table_text <- readLines(candidates[[1L]], warn = FALSE)
    template_line <- grep("^template_id:", table_text, value = TRUE)[[1L]]
    template_id <- sub("^template_id:[[:space:]]*'([^']+)'.*$", "\\1", template_line)
    template_lines <- readLines(file.path(template_dir, paste0(template_id, ".yaml")),
                                warn = FALSE)

    testthat::expect_equal(
      count_label_rows(readLines(sheet, warn = FALSE)),
      count_template_label_rows(template_lines),
      label = paste0(basename(sheet), " declared label rows vs ", template_id))
  }
})

# A section header that is indented exactly like its own statistics reads as a
# flat list: 14.1.2 shipped with all 32 rows at indent_level 0, so "Age (years)"
# was visually indistinguishable from its "n" row. The header must sit at 0 and
# everything it governs at 1.
testthat::test_that("section headers sit at indent 0 and their rows at indent 1", {
  template_dir <- file.path(project_root, "dummy_study", "metadata", "templates")
  for (name in c("tpl_baseline.yaml", "tpl_hgb_shift.yaml")) {
    lines <- readLines(file.path(template_dir, name), warn = FALSE)
    header_after_label <- 0L
    analysed_without_indent <- 0L
    for (i in seq_along(lines)) {
      line <- lines[[i]]
      if (!startsWith(trimws(line), "- id:")) next
      following <- lines[[i + 1L]]
      if (grepl("type: 'label'", following, fixed = TRUE)) {
        # Walk to the label's own indent_level, if it has one.
        block <- lines[i:min(length(lines), i + 3L)]
        if (any(grepl("indent_level: 1", block, fixed = TRUE))) header_after_label <- header_after_label + 1L
        next
      }
      if (!grepl("type: 'analysis'", following, fixed = TRUE)) next
      if (!grepl("indent_level: 1", following, fixed = TRUE)) analysed_without_indent <- analysed_without_indent + 1L
    }
    testthat::expect_equal(header_after_label, 0L, label = paste(name, "indented headers"))
    testthat::expect_equal(analysed_without_indent, 0L, label = paste(name, "flat analysis rows"))
  }
})
