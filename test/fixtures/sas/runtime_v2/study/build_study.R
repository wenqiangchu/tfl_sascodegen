# Explicit migration of the three historical study bundles; no SAS is run here.
source("test/fixtures/sas/runtime_v2/support.R")
target <- "study/validation_v2"
sources <- list(
  legacy = list(zip = "study/validation/validation_metadata.zip", programs = "study/validation"),
  severity = list(zip = "study/validation/metadata_14314.zip", programs = "study/validation"),
  ref_141 = list(zip = "study/validation_141/metadata_141.zip", programs = "study/validation_141")
)
# These choices reproduce the historical SAS: categorical USUBJID NODUPKEY,
# continuous source-row observations passed directly to PROC MEANS.
units <- c(disposition = "distinct_subject", teae = "distinct_subject",
           sex = "distinct_subject", age_group = "distinct_subject",
           ethnicity = "distinct_subject", race = "distinct_subject", bmi_group = "distinct_subject",
           age = "record", height = "record", weight = "record", bmi = "record",
           education = "record", mmse = "record", adas = "record")
ledger <- list()
cases <- list()
for (bundle_id in names(sources)) {
  input <- sources[[bundle_id]]
  entries <- read_archive_entries(readBin(input$zip, "raw", n = file.info(input$zip)$size))
  stopifnot(is.null(entries$error))
  values <- lapply(entries$entries, function(bytes) {
    parsed <- parse_yaml_document_text(rawToChar(bytes))
    stopifnot(length(parsed$errors) == 0L)
    parsed$value
  })
  stopifnot(values[["manifest.yaml"]]$schema_version == 1L)
  bundle <- new_metadata_bundle(
    populations = values[["populations.yaml"]]$populations,
    headers = values[["headers.yaml"]]$headers,
    tables = unname(values[grepl("^tables/", names(values))]),
    templates = unname(values[grepl("^templates/", names(values))])
  )
  changes <- list(list(path = "manifest.schema_version", old = 1L, new = 2L,
                       basis = "Approved explicit v2 migration; no application compatibility branch."))
  for (ti in seq_along(bundle$templates)) {
    template <- bundle$templates[[ti]]
    for (ci in seq_along(template$body$chunks)) {
      chunk <- template$body$chunks[[ci]]
      prefix <- paste(template$id, chunk$id, sep = "/")
      if (chunk$type != "hierarchical_summary") {
        stopifnot(is.null(chunk$counting_unit), chunk$id %in% names(units))
        chunk$counting_unit <- unname(units[[chunk$id]])
        changes[[length(changes) + 1L]] <- list(path = paste0(prefix, "/counting_unit"),
          new = chunk$counting_unit, basis = "Historical SAS subject NODUPKEY or source-row MEANS; explicit mapping in build_study.R.")
      }
      if (!is.null(chunk$source_contract)) {
        changes[[length(changes) + 1L]] <- list(path = paste0(prefix, "/source_contract"),
          old = chunk$source_contract, basis = "Retired object; current subject key is fixed USUBJID. Nested counting units are retained.")
        chunk$source_contract <- NULL
      }
      if (!is.null(chunk$denominator)) {
        stopifnot(identical(chunk$denominator, list(type = "header_population")))
        chunk$denominator <- list(scope = "header_population", unit = "distinct_subject")
        changes[[length(changes) + 1L]] <- list(path = paste0(prefix, "/denominator"),
          old = list(type = "header_population"), new = chunk$denominator,
          basis = "Approved denominator migration table, primitive header_population.")
      }
      template$body$chunks[[ci]] <- chunk
    }
    bundle$templates[[ti]] <- template
  }
  parsed <- parse_bundle_value(bundle)
  stopifnot(length(parsed$errors) == 0L)
  bundle <- parsed$value
  archive <- canonical_archive_bytes(bundle)
  restored <- runtime_require(parse_bundle_archive(archive))$workspace
  stopifnot(identical(archive$bytes, canonical_archive_bytes(restored)$bytes))
  destination <- file.path(target, "bundles", bundle_id)
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  file.copy(input$zip, file.path(destination, "original_v1.zip"), overwrite = TRUE)
  writeBin(archive$bytes, file.path(destination, "metadata_v2.zip"))
  texts <- encode_archive_texts(restored)
  for (entry in names(texts)) runtime_write(sub("\n$", "", texts[[entry]]),
                                           file.path(destination, "metadata", entry))
  for (table in restored$tables) {
    case_id <- paste(bundle_id, table$id, sep = "__")
    for (mode in c("report", "compare")) {
      generated <- runtime_require(generate_table_source(restored, table$id, output_mode = mode))
      repeated <- runtime_require(generate_table_source(restored, table$id, output_mode = mode))
      stopifnot(identical(generated$source, repeated$source))
      runtime_write(generated$source, file.path(target, "generated", case_id, paste0(mode, ".sas")))
    }
    cases[[length(cases) + 1L]] <- list(case_id = case_id, bundle = bundle_id, table_id = table$id,
      old_program = file.path(input$programs, paste0(table$id, ".sas")),
      old_rtf = file.path(input$programs, paste0(table$id, ".rtf")),
      template = find_object_by_id(restored$templates, table$template_id),
      header = find_object_by_id(restored$headers, table$header_id),
      population = find_object_by_id(restored$populations, table$population_id))
  }
  ledger[[bundle_id]] <- list(original = input$zip, changes = changes,
                            canonical_roundtrip = TRUE, deterministic_generation = TRUE)
}
jsonlite::write_json(ledger, file.path(target, "migration.json"), auto_unbox = TRUE, pretty = TRUE)
jsonlite::write_json(cases, file.path(target, "cases.json"), auto_unbox = TRUE, pretty = TRUE)
cat("Migrated three bundles and generated Report/QC for", length(cases), "configurations.\n")
