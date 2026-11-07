#!/usr/bin/env Rscript
# Run the generated dummy study programs in real SAS.
#
# Each table program is wrapped so that the study data are bound to a libref, the
# program is included unchanged, and the assembled report rows are persisted for
# independent checking. The SAS log is the primary evidence: a run only counts as
# successful when the log contains no ERROR record, because SAS can exit with 0
# while a program has failed.
#
# Usage (from the repository root):
#   Rscript dummy_study/tools/run_sas.R                # all tables
#   Rscript dummy_study/tools/run_sas.R --table t_14_1_1_disposition

args <- commandArgs(trailingOnly = TRUE)
table_flag <- match("--table", args)
only_table <- if (!is.na(table_flag) && length(args) > table_flag) args[[table_flag + 1L]] else NULL

sas_exe <- "E:/sas/SASFoundation/9.4/sas.exe"
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
data_dir <- file.path(root, "dummy_study", "data")
program_dir <- file.path(root, "dummy_study", "generated", "sas")
run_dir <- file.path(root, "dummy_study", "generated", "sasrun")
out_dir <- file.path(root, "dummy_study", "generated", "sasout")

if (!file.exists(sas_exe)) {
  stop("SAS executable not found: ", sas_exe, call. = FALSE)
}
programs <- sort(list.files(program_dir, pattern = "\\.sas$", full.names = TRUE))
if (!is.null(only_table)) {
  programs <- programs[sub("\\.sas$", "", basename(programs)) == only_table]
  if (length(programs) == 0L) stop("No program for table: ", only_table, call. = FALSE)
}
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_text <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(lines), path, useBytes = TRUE)
}

# SAS messages appear in English even when the installed locale is not; the
# record tag is the stable part to match.
log_records <- function(log_lines, tag) {
  pattern <- paste0("^\\s*", tag, "(:|\\s)")
  grep(pattern, log_lines, value = TRUE)
}

# Warnings fall into classes this study does not control: site installation
# entries, and the source-grain diagnostics the emitters emit by design (an AE
# source has many records per subject, and the guard reports that without
# changing records). Anything unclassified must be read by a human, so it fails
# the run instead of hiding in a total.
classify_warning <- function(line) {
  # The site warning about missing SASHELP entries is emitted as two WARNING
  # records; the continuation line carries no library name, so match its text.
  if (grepl("SASHELP|SASUSER", line) || grepl("已从连接中删除", line, fixed = TRUE)) {
    return("environment_missing_library_entries")
  }
  if (grepl("[USER] duplicate_key", line, fixed = TRUE)) {
    return("source_duplicate_diagnostic_records_preserved")
  }
  if (grepl("[USER] header_subject_duplicate", line, fixed = TRUE)) {
    return("header_subject_duplicate")
  }
  "unclassified"
}

results <- list()
for (program in programs) {
  id <- sub("\\.sas$", "", basename(program))
  wrapper <- file.path(run_dir, paste0(id, ".sas"))
  log_path <- file.path(run_dir, paste0(id, ".log"))
  lst_path <- file.path(run_dir, paste0(id, ".lst"))
  rtf_path <- file.path(run_dir, paste0(id, ".rtf"))
  unlink(c(log_path, lst_path, rtf_path))

  write_text(c(
    sprintf('libname study "%s";', data_dir),
    sprintf('libname tflout "%s";', out_dir),
    sprintf('%%include "%s";', program),
    "",
    "/* Persist the report rows so the numbers can be checked outside SAS. */",
    sprintf("data tflout.wide_%s;", id),
    "  set _TFL_WIDE_001;",
    "run;",
    sprintf("data tflout.asm_%s;", id),
    "  set _TFL_ASM_001;",
    "run;",
    "/* Persist the paginated rows too: page grouping is a layout contract that no",
    "   other artifact exposes, and the padding invariant is checked on it. */",
    sprintf("data tflout.paged_%s;", id),
    "  set _TFL_PAGED_001;",
    "run;",
    "",
    "/* Report the row count in the log so the runner needs no SAS data reader. */",
    sprintf("%%let _tfl_dsid = %%sysfunc(open(tflout.wide_%s));", id),
    sprintf("%%put NOTE: [USER] tfl_obs_%s=%%sysfunc(attrn(&_tfl_dsid, NOBS));", id),
    "%let _tfl_dsid = %sysfunc(close(&_tfl_dsid));",
    ""
  ), wrapper)

  # Same invocation the external runtime harness uses: relative file names, a
  # batch-only terminal, and no shell quoting. The program writes its RTF to the
  # process working directory, so the run directory becomes the cwd.
  old_wd <- setwd(run_dir)
  exit_code <- tryCatch(
    system2(sas_exe, c("-sysin", basename(wrapper), "-log", basename(log_path),
                       "-print", basename(lst_path), "-nosplash", "-noterminal")),
    finally = setwd(old_wd)
  )
  if (!is.numeric(exit_code)) exit_code <- 0L

  log_lines <- if (file.exists(log_path)) readLines(log_path, warn = FALSE) else character()
  errors <- log_records(log_lines, "ERROR")
  warnings <- log_records(log_lines, "WARNING")

  obs_pattern <- paste0("tfl_obs_", id, "=([0-9]+)")
  obs_hit <- regmatches(log_lines, regexpr(obs_pattern, log_lines))
  wide_obs <- if (length(obs_hit) > 0L) {
    as.integer(sub(paste0(".*tfl_obs_", id, "="), "", obs_hit[[1L]]))
  } else {
    NA_integer_
  }

  results[[id]] <- list(
    table = id,
    exit_code = exit_code,
    error_count = length(errors),
    warning_count = length(warnings),
    warning_classes = as.list(table(vapply(warnings, classify_warning, character(1L)))),
    unclassified_warnings = unname(warnings[
      vapply(warnings, classify_warning, character(1L)) == "unclassified"]),
    errors = unname(errors),
    warnings = unname(warnings),
    log = log_path,
    rtf_bytes = if (file.exists(rtf_path)) file.info(rtf_path)$size else 0,
    wide_obs = wide_obs,
    dataset = file.path(out_dir, paste0("wide_", id, ".sas7bdat"))
  )
  cat(sprintf("%-28s exit=%d errors=%d warnings=%d unclassified=%d obs=%s rtf=%s\n",
              id, exit_code, length(errors), length(warnings),
              length(results[[id]]$unclassified_warnings),
              ifelse(is.na(wide_obs), "?", wide_obs),
              if (results[[id]]$rtf_bytes > 0) format(results[[id]]$rtf_bytes) else "MISSING"))
  for (line in errors) cat("    ", trimws(line), "\n", sep = "")
  for (line in results[[id]]$unclassified_warnings) {
    cat("  W ", trimws(line), "\n", sep = "")
  }
}

summary_path <- file.path(run_dir, "summary.json")
writeLines(jsonlite::toJSON(results, auto_unbox = TRUE, pretty = TRUE), summary_path,
           useBytes = TRUE)

failed <- vapply(results, function(r) {
  r$error_count > 0L || r$exit_code != 0L || length(r$unclassified_warnings) > 0L
}, logical(1L))
cat(sprintf("\n%d/%d programs clean; summary: %s\n", sum(!failed), length(failed), summary_path))
if (any(failed)) quit(status = 1L)
