#!/usr/bin/env Rscript
# Compute the expected statistics for every dummy study table, in R.
#
# This is deliberately an independent second implementation: it reads the raw
# study datasets with haven and derives each cell from first principles, without
# reusing the metadata, the emitters, or any generated SAS. The result is written
# as a long table so compare_with_sas.R can join it to the SAS output cell by
# cell.
#
# Quantiles are computed and recorded but flagged asserted = FALSE: PROC MEANS
# uses PCTLDEF = 5 by default and R's quantile() has nine types, so agreement is
# worth reporting but not worth failing on.
#
# Usage (from the repository root):
#   Rscript dummy_study/verify/compute_expected.R

suppressPackageStartupMessages(library(haven))

data_dir <- file.path("dummy_study", "data")
out_dir <- file.path("dummy_study", "generated", "expected")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

read_dataset <- function(name) {
  data <- haven::read_sas(file.path(data_dir, paste0(name, ".sas7bdat")))
  for (column in names(data)) {
    if (is.character(data[[column]])) {
      values <- trimws(data[[column]])
      values[values == ""] <- NA_character_
      data[[column]] <- values
    }
  }
  data
}

adsl <- read_dataset("adsl")
adae <- read_dataset("adae")
adlbh <- read_dataset("adlbh")

arm_values <- c(placebo = "Placebo", low = "Xanomeline Low Dose",
                high = "Xanomeline High Dose")
column_ids <- c("placebo", "low", "high", "overall")

# Sample standard deviation, matching PROC MEANS. stats::sd() returns NA for a
# single observation, and so does SAS, so they agree by construction.
summary_stats <- function(values) {
  values <- values[!is.na(values)]
  n <- length(values)
  if (n == 0L) {
    return(list(n = 0L, mean = NA_real_, sd = NA_real_, median = NA_real_,
                q1 = NA_real_, q3 = NA_real_, min = NA_real_, max = NA_real_))
  }
  quantiles <- stats::quantile(values, probs = c(0.25, 0.5, 0.75), names = FALSE,
                               type = 2)
  list(n = n, mean = mean(values), sd = if (n > 1L) stats::sd(values) else NA_real_,
       median = quantiles[[2L]], q1 = quantiles[[1L]], q3 = quantiles[[3L]],
       min = min(values), max = max(values))
}

stat_names <- c("n", "mean", "sd", "median", "q1", "q3", "min", "max")
# Only these statistics are asserted; see the header comment.
asserted_stats <- c("n", "mean", "sd", "min", "max")

emit <- function(collector, table, path, label, level, column_id, values,
                 asserted = asserted_stats) {
  for (stat in names(values)) {
    collector[[length(collector) + 1L]] <- data.frame(
      table = table, path = path, label = label, level = level,
      column_id = column_id, stat = stat, value = as.numeric(values[[stat]]),
      asserted = stat %in% asserted, stringsAsFactors = FALSE)
  }
  collector
}

# --- header counts -----------------------------------------------------------

header_counts <- function(data, variable) {
  counts <- vapply(arm_values, function(arm) sum(data[[variable]] == arm, na.rm = TRUE),
                   numeric(1L))
  c(as.list(counts), list(overall = nrow(data)))
}

disposition_header <- header_counts(adsl, "TRT01P")
analysis_header <- header_counts(adsl, "TRT01A")

# --- 14.1.1 Subject disposition ---------------------------------------------

disposition_rows <- list(
  list(label = "Randomized", indent = 0, predicate = function(d) rep(TRUE, nrow(d))),
  list(label = "Intent-to-Treat Population", indent = 0,
       predicate = function(d) d$ITTFL == "Y"),
  list(label = "Safety Population", indent = 0, predicate = function(d) d$SAFFL == "Y"),
  list(label = "Efficacy Population", indent = 0, predicate = function(d) d$EFFFL == "Y"),
  list(label = "Completed Study", indent = 0, predicate = function(d) d$EOSSTT == "COMPLETED"),
  list(label = "Discontinued Study", indent = 0,
       predicate = function(d) d$EOSSTT == "DISCONTINUED")
)
for (reason in sort(unique(stats::na.omit(adsl$DCSREAS)))) {
  disposition_rows[[length(disposition_rows) + 1L]] <- list(
    label = reason, indent = 1,
    predicate = local({
      value <- reason
      function(d) !is.na(d$DCSREAS) & d$DCSREAS == value
    })
  )
}

expected <- list()
for (row in disposition_rows) {
  selected <- row$predicate(adsl)
  for (column_id in column_ids) {
    if (identical(column_id, "overall")) {
      in_column <- rep(TRUE, nrow(adsl))
    } else {
      in_column <- adsl$TRT01P == arm_values[[column_id]]
    }
    n <- sum(selected & in_column, na.rm = TRUE)
    denominator <- if (identical(column_id, "overall")) nrow(adsl) else
      sum(in_column, na.rm = TRUE)
    expected <- emit(expected, "t_14_1_1_disposition", row$label, row$label,
                     row$indent, column_id,
                     list(n = n, pct = if (denominator > 0L) 100 * n / denominator else NA_real_),
                     asserted = c("n", "pct"))
  }
}

# --- 14.1.2 Demographics and baseline characteristics ------------------------

continuous_variables <- list(
  list(path = "Age (years)", variable = "AGE", digits = 1),
  list(path = "Baseline Body Mass Index (kg/m2)", variable = "BMIBL", digits = 2),
  list(path = "Disease Duration (months)", variable = "DURDIS", digits = 1)
)
for (spec in continuous_variables) {
  for (column_id in column_ids) {
    in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(adsl)) else
      adsl$TRT01P == arm_values[[column_id]]
    values <- summary_stats(adsl[[spec$variable]][in_column])
    expected <- emit(expected, "t_14_1_2_baseline", spec$path, spec$path, 0L,
                     column_id, values)
  }
}

# The report prints the display label declared in the shell, which is not always
# the stored value. This map is part of the specification, so reproducing it in
# R is not borrowing from the SAS implementation.
display_labels <- list(
  SEX = c(F = "Female", M = "Male"),
  RACE = c(WHITE = "White",
           `BLACK OR AFRICAN AMERICAN` = "Black or African American",
           `AMERICAN INDIAN OR ALASKA NATIVE` = "American Indian or Alaska Native"),
  DURDSGR1 = c(`<12` = "< 12 months", `>=12` = ">= 12 months")
)

categorical_variables <- list(
  list(variable = "AGEGR1"),
  list(variable = "SEX"),
  list(variable = "RACE"),
  list(variable = "DURDSGR1")
)
for (spec in categorical_variables) {
  for (level_value in sort(unique(stats::na.omit(adsl[[spec$variable]])))) {
    labels <- display_labels[[spec$variable]]
    path <- if (!is.null(labels) && level_value %in% names(labels)) {
      unname(labels[[level_value]])
    } else {
      level_value
    }
    for (column_id in column_ids) {
      in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(adsl)) else
        adsl$TRT01P == arm_values[[column_id]]
      n <- sum(in_column & !is.na(adsl[[spec$variable]]) &
                 adsl[[spec$variable]] == level_value, na.rm = TRUE)
      denominator <- sum(in_column, na.rm = TRUE)
      expected <- emit(expected, "t_14_1_2_baseline", path, level_value, 1L,
                       column_id,
                       list(n = n, pct = 100 * n / denominator),
                       asserted = c("n", "pct"))
    }
  }
}

# --- 14.3.2.1 Hemoglobin by visit -------------------------------------------

hgb <- adlbh[!is.na(adlbh$PARAMCD) & adlbh$PARAMCD == "HGB", ]
visits <- unique(hgb[order(hgb$AVISITN), c("AVISITN", "AVISIT")])
visits <- visits[!is.na(visits$AVISIT), ]
for (visit_index in seq_len(nrow(visits))) {
  visit <- visits$AVISIT[[visit_index]]
  path <- paste("Hemoglobin (mmol/L)", visit, sep = " / ")
  for (column_id in column_ids) {
    in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(hgb)) else
      hgb$TRTA == arm_values[[column_id]]
    values <- summary_stats(hgb$AVAL[in_column & !is.na(hgb$AVISIT) & hgb$AVISIT == visit])
    expected <- emit(expected, "t_14_3_2_1_hgb_by_visit", path, visit, 2L,
                     column_id, values)
  }
}

# --- 14.2.3 Hemoglobin shift -------------------------------------------------

# Independent re-derivation of WORK.SHIFT_HGB: one row per subject with a
# baseline grade, carrying the worst post-baseline grade, with the baseline grade
# carried forward when no post-baseline grade exists.
grade_rank <- c(NORMAL = 0, LOW = 1, HIGH = 2)
baseline <- hgb[!is.na(hgb$ABLFL) & hgb$ABLFL == "Y" & !is.na(hgb$LBNRIND), ]
post <- hgb[is.na(hgb$ABLFL), ]
worst <- vapply(split(post$LBNRIND, post$USUBJID), function(grades) {
  # Keep only the grades this study ranks; anything else must not silently win
  # the comparison through a missing index.
  grades <- grades[!is.na(grades) & grades %in% names(grade_rank)]
  if (length(grades) == 0L) return(NA_character_)
  grades[[which.max(grade_rank[grades])]]
}, character(1L))
shift_data <- data.frame(
  USUBJID = baseline$USUBJID,
  TRTA = baseline$TRTA,
  LBNRIND_BL = baseline$LBNRIND,
  stringsAsFactors = FALSE
)
shift_data$ANRIND_WORST <- unname(worst[shift_data$USUBJID])
shift_data$ANRIND_WORST[is.na(shift_data$ANRIND_WORST)] <-
  shift_data$LBNRIND_BL[is.na(shift_data$ANRIND_WORST)]

shift_columns <- c(bl_normal = "NORMAL", bl_low = "LOW", bl_high = "HIGH")
for (arm_id in c("placebo", "low", "high")) {
  arm <- arm_values[[arm_id]]
  section <- shift_data[shift_data$TRTA == arm, ]
  for (worst_grade in c("NORMAL", "LOW", "HIGH")) {
    n_total <- sum(section$ANRIND_WORST == worst_grade, na.rm = TRUE)
    for (column_id in c(names(shift_columns), "overall")) {
      in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(section)) else
        section$LBNRIND_BL == shift_columns[[column_id]]
      denominator <- sum(in_column, na.rm = TRUE)
      n <- sum(in_column & section$ANRIND_WORST == worst_grade, na.rm = TRUE)
      # The section is a chunk, so the report prints only the row label; the
      # path carries the arm to keep the three sections apart.
      # The report prints the row title with capitalisation only ("High"), so the
      # path uses the display form rather than the stored grade.
      display <- paste0(substr(worst_grade, 1L, 1L), tolower(substr(worst_grade, 2L, nchar(worst_grade))))
      path <- paste(arm, display, sep = " / ")
      expected <- emit(expected, "t_14_2_3_hgb_shift", path, display, 0L,
                       column_id,
                       list(n = n, pct = if (denominator > 0L) 100 * n / denominator
                             else NA_real_),
                       asserted = c("n", "pct"))
    }
  }
}

# --- TEAE derivations shared by 14.3.1.2 and 14.3.1.4 ----------------------

teae <- adae[!is.na(adae$TRTEMFL) & adae$TRTEMFL == "Y" &
               !is.na(adae$SAFFL) & adae$SAFFL == "Y", ]

# Count distinct subjects per SOC and per (SOC, PT). Keeping the two labels as
# columns avoids ever reconstructing them from a concatenated key, which would
# truncate multi-word terms such as "ATRIAL FIBRILLATION".
count_subjects <- function(subjects) {
  soc_counts <- stats::aggregate(USUBJID ~ AEBODSYS, data = subjects,
                                 FUN = function(x) length(unique(x)))
  names(soc_counts)[[2L]] <- "n"
  pt_counts <- stats::aggregate(USUBJID ~ AEBODSYS + AEDECOD, data = subjects,
                                FUN = function(x) length(unique(x)))
  names(pt_counts)[[3L]] <- "n"
  list(soc = soc_counts, pt = pt_counts)
}

# --- 14.3.1.2 TEAE by SOC and PT -------------------------------------------

soc_universe <- sort(unique(teae$AEBODSYS[!is.na(teae$AEBODSYS)]))
pt_universe <- unique(teae[!is.na(teae$AEBODSYS) & !is.na(teae$AEDECOD),
                           c("AEBODSYS", "AEDECOD")])
pt_universe <- pt_universe[order(pt_universe$AEBODSYS, pt_universe$AEDECOD), ]

for (column_id in column_ids) {
  in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(teae)) else
    teae$TRTA == arm_values[[column_id]]
  denominator <- if (identical(column_id, "overall")) 254 else
    sum(adsl$TRT01A == arm_values[[column_id]], na.rm = TRUE)

  any_n <- length(unique(teae$USUBJID[in_column]))
  expected <- emit(expected, "t_14_3_1_2_teae", "At Least One TEAE",
                   "At Least One TEAE", 0L, column_id,
                   list(n = any_n, pct = 100 * any_n / denominator),
                   asserted = c("n", "pct"))

  counts <- count_subjects(teae[in_column, c("USUBJID", "AEBODSYS", "AEDECOD")])
  # The report prints every node in every column, and a node missing from one arm
  # prints 0 rather than disappearing, so the loop walks the whole node universe.
  for (soc in soc_universe) {
    hit <- counts$soc$n[!is.na(counts$soc$AEBODSYS) & counts$soc$AEBODSYS == soc]
    n <- if (length(hit) == 0L) 0L else as.integer(hit[[1L]])
    expected <- emit(expected, "t_14_3_1_2_teae", soc, soc, 1L, column_id,
                     list(n = n, pct = 100 * n / denominator),
                     asserted = c("n", "pct"))
  }
  for (i in seq_len(nrow(pt_universe))) {
    soc <- pt_universe$AEBODSYS[[i]]
    pt <- pt_universe$AEDECOD[[i]]
    hit <- counts$pt$n[!is.na(counts$pt$AEBODSYS) & counts$pt$AEBODSYS == soc &
                         !is.na(counts$pt$AEDECOD) & counts$pt$AEDECOD == pt]
    n <- if (length(hit) == 0L) 0L else as.integer(hit[[1L]])
    expected <- emit(expected, "t_14_3_1_2_teae", paste(soc, pt, sep = " / "), pt,
                     2L, column_id, list(n = n, pct = 100 * n / denominator),
                     asserted = c("n", "pct"))
  }
}

# --- 14.3.1.4 TEAE by SOC and PT, each with its own severity breakdown -------

# The report nests severity *inside* both SOC and PT, so the same subject can be
# counted at several severity rows of one SOC. The SOC-level breakdown reduces
# each subject to their worst severity within that SOC; the PT-level breakdown
# keeps the worst severity within the SOC/PT pair. These are different numbers
# and the fixture asserts both.
severity_order <- c(SEVERE = 1L, MODERATE = 2L, MILD = 3L)
teae_severity <- teae
teae_severity$SEV_ORDER <- unname(severity_order[teae_severity$AESEV])
severity_codes <- c(SEVERE = 1L, MODERATE = 2L, MILD = 3L)

# Worst severity per subject x SOC x PT, which is what WORK.AE_MAXSEV holds.
pt_key <- c("USUBJID", "TRTA", "AEBODSYS", "AEDECOD")
pt_reduced <- stats::aggregate(teae_severity$SEV_ORDER, by = teae_severity[pt_key],
                               FUN = min)
names(pt_reduced)[[length(names(pt_reduced))]] <- "SEV_ORDER"

# Worst severity per subject x SOC, collapsing that subject's PTs in the SOC.
soc_key <- c("USUBJID", "TRTA", "AEBODSYS")
soc_reduced <- stats::aggregate(pt_reduced$SEV_ORDER, by = pt_reduced[soc_key],
                                FUN = min)
names(soc_reduced)[[length(names(soc_reduced))]] <- "SEV_ORDER"

subject_count <- function(frame) {
  if (nrow(frame) == 0L) return(0L)
  length(unique(frame$USUBJID))
}

# The node universe is data-wide, not per arm: a node an arm never reached still
# prints 0 rather than disappearing.
soc_universe <- sort(unique(soc_reduced$AEBODSYS))
pt_universe <- unique(pt_reduced[, c("AEBODSYS", "AEDECOD")])
pt_universe <- pt_universe[order(pt_universe$AEBODSYS, pt_universe$AEDECOD), ]

for (column_id in column_ids) {
  in_column <- function(frame) {
    if (identical(column_id, "overall")) rep(TRUE, nrow(frame)) else
      frame$TRTA == arm_values[[column_id]]
  }
  denominator <- if (identical(column_id, "overall")) 254 else
    sum(adsl$TRT01A == arm_values[[column_id]], na.rm = TRUE)
  soc_arm <- soc_reduced[in_column(soc_reduced), ]
  pt_arm <- pt_reduced[in_column(pt_reduced), ]

  for (soc in soc_universe) {
    soc_rows <- soc_arm[soc_arm$AEBODSYS == soc, ]
    n_soc <- subject_count(soc_rows)
    expected <- emit(expected, "t_14_3_1_4_teae_severity", soc, soc, 1L, column_id,
                     list(n = n_soc, pct = 100 * n_soc / denominator),
                     asserted = c("n", "pct"))
    for (severity_name in names(severity_codes)) {
      code <- severity_codes[[severity_name]]
      n_sev <- subject_count(soc_rows[!is.na(soc_rows$SEV_ORDER) &
                                        soc_rows$SEV_ORDER == code, ])
      expected <- emit(expected, "t_14_3_1_4_teae_severity",
                       paste(soc, severity_name, sep = " / "), severity_name, 2L,
                       column_id,
                       list(n = n_sev, pct = 100 * n_sev / denominator),
                       asserted = c("n", "pct"))
    }

    pts <- pt_universe$AEDECOD[pt_universe$AEBODSYS == soc]
    for (pt in pts) {
      pt_rows <- pt_arm[pt_arm$AEBODSYS == soc & pt_arm$AEDECOD == pt, ]
      n_pt <- subject_count(pt_rows)
      expected <- emit(expected, "t_14_3_1_4_teae_severity",
                       paste(soc, pt, sep = " / "), pt, 2L, column_id,
                       list(n = n_pt, pct = 100 * n_pt / denominator),
                       asserted = c("n", "pct"))
      for (severity_name in names(severity_codes)) {
        code <- severity_codes[[severity_name]]
        n_pt_sev <- subject_count(pt_rows[!is.na(pt_rows$SEV_ORDER) &
                                            pt_rows$SEV_ORDER == code, ])
        expected <- emit(expected, "t_14_3_1_4_teae_severity",
                         paste(soc, pt, severity_name, sep = " / "), severity_name,
                         3L, column_id,
                         list(n = n_pt_sev, pct = 100 * n_pt_sev / denominator),
                         asserted = c("n", "pct"))
      }
    }
  }
}

# --- 14.3.1.5 Serious TEAE by SOC and PT (format-driven levels) --------------

# This table exists to exercise format-driven levels, so the node universe is
# deliberately wider than the data: both levels declare a format and the report
# prints the full cross product, meaning all 23 SOCs and, under each of them,
# both formatted Preferred Terms. Only one SOC carries any serious event.
#
# The formats are written with NOTSORTED, so the SOC order is the declaration
# order in the table's custom_code.before, not the alphabetical order of the
# MedDRA strings. The expectations below therefore hard-code that declaration
# order instead of sorting, which is what makes the format ordering testable.
serious_soc_order <- c(
  "NERVOUS SYSTEM DISORDERS",
  "CARDIAC DISORDERS",
  "VASCULAR DISORDERS",
  "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS",
  "GASTROINTESTINAL DISORDERS",
  "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
  "MUSCULOSKELETAL AND CONNECTIVE TISSUE DISORDERS",
  "INFECTIONS AND INFESTATIONS",
  "INVESTIGATIONS",
  "INJURY, POISONING AND PROCEDURAL COMPLICATIONS",
  "METABOLISM AND NUTRITION DISORDERS",
  "PSYCHIATRIC DISORDERS",
  "RENAL AND URINARY DISORDERS",
  "EYE DISORDERS",
  "EAR AND LABYRINTH DISORDERS",
  "HEPATOBILIARY DISORDERS",
  "IMMUNE SYSTEM DISORDERS",
  "REPRODUCTIVE SYSTEM AND BREAST DISORDERS",
  "SOCIAL CIRCUMSTANCES",
  "SURGICAL AND MEDICAL PROCEDURES",
  "CONGENITAL, FAMILIAL AND GENETIC DISORDERS",
  "NEOPLASMS BENIGN, MALIGNANT AND UNSPECIFIED (INCL CYSTS AND POLYPS)",
  "GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS"
)
serious_pt_order <- c("SYNCOPE", "PARTIAL SEIZURES WITH SECONDARY GENERALISATION")

# The format labels are the display values the report prints.
serious_soc_label <- c(
  "NERVOUS SYSTEM DISORDERS" = "Nervous system disorders",
  "CARDIAC DISORDERS" = "Cardiac disorders",
  "VASCULAR DISORDERS" = "Vascular disorders",
  "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS" =
    "Respiratory, thoracic and mediastinal disorders",
  "GASTROINTESTINAL DISORDERS" = "Gastrointestinal disorders",
  "SKIN AND SUBCUTANEOUS TISSUE DISORDERS" = "Skin and subcutaneous tissue disorders",
  "MUSCULOSKELETAL AND CONNECTIVE TISSUE DISORDERS" =
    "Musculoskeletal and connective tissue disorders",
  "INFECTIONS AND INFESTATIONS" = "Infections and infestations",
  "INVESTIGATIONS" = "Investigations",
  "INJURY, POISONING AND PROCEDURAL COMPLICATIONS" =
    "Injury, poisoning and procedural complications",
  "METABOLISM AND NUTRITION DISORDERS" = "Metabolism and nutrition disorders",
  "PSYCHIATRIC DISORDERS" = "Psychiatric disorders",
  "RENAL AND URINARY DISORDERS" = "Renal and urinary disorders",
  "EYE DISORDERS" = "Eye disorders",
  "EAR AND LABYRINTH DISORDERS" = "Ear and labyrinth disorders",
  "HEPATOBILIARY DISORDERS" = "Hepatobiliary disorders",
  "IMMUNE SYSTEM DISORDERS" = "Immune system disorders",
  "REPRODUCTIVE SYSTEM AND BREAST DISORDERS" = "Reproductive system and breast disorders",
  "SOCIAL CIRCUMSTANCES" = "Social circumstances",
  "SURGICAL AND MEDICAL PROCEDURES" = "Surgical and medical procedures",
  "CONGENITAL, FAMILIAL AND GENETIC DISORDERS" =
    "Congenital, familial and genetic disorders",
  "NEOPLASMS BENIGN, MALIGNANT AND UNSPECIFIED (INCL CYSTS AND POLYPS)" =
    "Neoplasms benign, malignant and unspecified (incl cysts and polyps)",
  "GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS" =
    "General disorders and administration site conditions"
)
serious_pt_label <- c(
  "SYNCOPE" = "Syncope",
  "PARTIAL SEIZURES WITH SECONDARY GENERALISATION" =
    "Partial seizures with secondary generalisation"
)

serious <- teae[!is.na(teae$AESER) & teae$AESER == "Y", ]
stopifnot(setequal(unique(serious$AEBODSYS), "NERVOUS SYSTEM DISORDERS"))
stopifnot(all(unique(serious$AEDECOD) %in% serious_pt_order))

for (column_id in column_ids) {
  in_column <- if (identical(column_id, "overall")) rep(TRUE, nrow(serious)) else
    serious$TRTA == arm_values[[column_id]]
  denominator <- if (identical(column_id, "overall")) nrow(adsl) else
    sum(adsl$TRT01A == arm_values[[column_id]], na.rm = TRUE)
  serious_arm <- serious[in_column, ]

  for (soc in serious_soc_order) {
    soc_label <- serious_soc_label[[soc]]
    soc_rows <- serious_arm[!is.na(serious_arm$AEBODSYS) &
                              serious_arm$AEBODSYS == soc, ]
    n_soc <- subject_count(soc_rows)
    expected <- emit(expected, "t_14_3_1_5_serious_teae", soc_label, soc_label, 1L,
                     column_id, list(n = n_soc, pct = 100 * n_soc / denominator),
                     asserted = c("n", "pct"))
    for (pt in serious_pt_order) {
      pt_label <- serious_pt_label[[pt]]
      pt_rows <- soc_rows[!is.na(soc_rows$AEDECOD) & soc_rows$AEDECOD == pt, ]
      n_pt <- subject_count(pt_rows)
      expected <- emit(expected, "t_14_3_1_5_serious_teae",
                       paste(soc_label, pt_label, sep = " / "), pt_label, 2L,
                       column_id, list(n = n_pt, pct = 100 * n_pt / denominator),
                       asserted = c("n", "pct"))
    }
  }
}

# --- write -------------------------------------------------------------------

result <- do.call(rbind, expected)
result <- result[order(result$table, result$path, result$column_id, result$stat), ]

# The cell comparison is keyed, so it cannot see display order. For the table
# whose levels are format-driven the order *is* the behaviour under test, so the
# expected sequence of report rows is written alongside the cells. It comes from
# the format declaration order, which NOTSORTED preserves; without NOTSORTED SAS
# falls back to the raw value order and this sequence would no longer match.
node_order_path <- file.path(out_dir, "node_order.csv")
declared_soc_order <- vapply(serious_soc_order, function(soc) serious_soc_label[[soc]],
                             character(1L), USE.NAMES = FALSE)
order_rows <- unlist(lapply(declared_soc_order, function(soc_label) {
  c(soc_label, unlist(lapply(unname(serious_pt_label), function(pt_label) {
    paste(soc_label, pt_label, sep = " / ")
  })))
}))
utils::write.csv(data.frame(table = "t_14_3_1_5_serious_teae",
                            position = seq_along(order_rows),
                            path = order_rows,
                            stringsAsFactors = FALSE),
                 node_order_path, row.names = FALSE)
row.names(result) <- NULL
utils::write.csv(result, file.path(out_dir, "expected.csv"), row.names = FALSE)

for (table in unique(result$table)) {
  rows <- result[result$table == table, ]
  cat(sprintf("%-28s %5d cells over %3d paths\n", table, nrow(rows),
              length(unique(rows$path))))
}
cat(sprintf("\nwrote %s\n", file.path(out_dir, "expected.csv")))
