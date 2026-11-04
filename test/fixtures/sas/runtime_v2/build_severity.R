source("test/fixtures/sas/runtime_v2/support.R")
source("test/fixtures/sas/runtime_v2/format_cases.R")
bundle <- format_case("basic")$bundle
before <- c(
  "data work.rv_adsl; length USUBJID $2; input USUBJID $; datalines;", "01", "02", "03", ";", "run;",
  "data work.rv_events; length USUBJID $2 SOC $5 PT $12; input USUBJID $ SOC $ PT $ SEV; datalines;",
  "01 GI Nausea 1", "01 GI Nausea 2", "01 GI Diarrhoea 3", "02 GI Nausea 1",
  "02 GI Diarrhoea 1", "03 Neuro Headache 2", ";", "run;",
  "proc sql;",
  "  create table rv_soc_max as select USUBJID,SOC,max(SEV) as SOC_MAX_SEV from rv_events group by USUBJID,SOC;",
  "  create table rv_pt_max as select USUBJID,SOC,PT,max(SEV) as PT_MAX_SEV from rv_events group by USUBJID,SOC,PT;",
  "  create table rv_prepared as select e.*,s.SOC_MAX_SEV,p.PT_MAX_SEV from rv_events e",
  "    left join rv_soc_max s on e.USUBJID=s.USUBJID and e.SOC=s.SOC",
  "    left join rv_pt_max p on e.USUBJID=p.USUBJID and e.SOC=p.SOC and e.PT=p.PT;",
  "quit;"
)
bundle$tables[[1L]]$id <- "rv_severity"
bundle$tables[[1L]]$custom_code$before <- paste(before, collapse = "\n")
make_block <- function(level, distribution) {
  id <- paste0(level, if (distribution) "_severity" else "_count")
  rows <- lapply(if (distribution) 1:3 else 0L, function(severity) list(
    id = if (distribution) c("mild", "moderate", "severe")[[severity]] else "total",
    type = "analysis", label = if (distribution) c("Mild", "Moderate", "Severe")[[severity]] else "Subjects",
    condition = if (distribution) paste0(toupper(level), "_MAX_SEV=", severity) else "1",
    statistics = list(list(id = "n"), list(id = "pct", digits = 1L)), cell_format = "{n}|{pct}"))
  list(id = id, anchor_level = level, placement = if (distribution) "below" else "same_row",
       type = "categorical_summary_nonexclusive", counting_unit = "distinct_subject",
       denominator = list(scope = if (distribution) "current_group" else "header_population", unit = "distinct_subject"), rows = rows)
}
bundle$templates[[1L]]$body$chunks <- list(list(id = "severity", type = "hierarchical_summary", source_data = "work.rv_prepared",
  levels = lapply(c("soc", "pt"), function(level) list(id = level, variable = toupper(level), order_variable = toupper(level),
    order_direction = "asc", node_role = "analysis", node_analysis_id = paste0(level, "_count"), missing_policy = "exclude")),
  analysis_blocks = list(make_block("soc", FALSE), make_block("soc", TRUE), make_block("pt", FALSE), make_block("pt", TRUE))))
counts <- list("GI" = c(2,1,0), "GI/Diarrhoea" = c(2,1,0), "GI/Nausea" = c(2,1,0),
               "Neuro" = c(1,0,0), "Neuro/Headache" = c(1,0,0))
distributions <- list("GI" = list(c(1,0,0),c(0,0,0),c(1,1,0)),
  "GI/Diarrhoea" = list(c(1,0,0),c(0,0,0),c(1,1,0)),
  "GI/Nausea" = list(c(1,0,0),c(1,1,0),c(0,0,0)),
  "Neuro" = list(c(0,0,0),c(1,0,0),c(0,0,0)),
  "Neuro/Headache" = list(c(0,0,0),c(1,0,0),c(0,0,0)))
expected <- list()
for (path in names(counts)) {
  expected[[length(expected)+1L]] <- list(row_id = "total", path = path, n = counts[[path]], denominator = c(3,1,0))
  for (i in 1:3) expected[[length(expected)+1L]] <- list(row_id = c("mild","moderate","severe")[[i]],
    path = path, n = distributions[[path]][[i]], denominator = counts[[path]])
}
destination <- "study/validation_v2/severity_case"
runtime_write(runtime_require(generate_table_source(bundle, "rv_severity", include_duplicate_check = FALSE))$source,
              file.path(destination, "program.sas"))
writeBin(canonical_archive_bytes(bundle)$bytes, file.path(destination, "metadata.zip"))
jsonlite::write_json(list(expected = expected, header_n = c(3,1,0)), file.path(destination,"expected.json"), auto_unbox = TRUE, pretty = TRUE)
