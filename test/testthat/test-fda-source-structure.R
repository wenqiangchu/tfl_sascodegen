testthat::test_that("FDA-style tables generate expected source sections", {
  zip_path <- file.path(project_root, "test", "fixtures", "demo_metadata.zip")
  bytes <- readBin(zip_path, "raw", n = file.info(zip_path)$size)
  imported <- application_import_bundle(new_empty_workspace(), bytes)
  testthat::expect_true(imported$passed)
  ws <- imported$workspace
  ids <- vapply(ws$tables, `[[`, "", "id")
  for (id in c("z_ae_overview", "z_lab_change_over_time")) testthat::expect_true(id %in% ids)
  ae <- application_generate_source(ws, "z_ae_overview")
  testthat::expect_true(ae$passed)
  testthat::expect_equal(length(regmatches(ae$value, gregexpr("proc freq", ae$value, fixed=TRUE))[[1L]]), 1L)
  testthat::expect_match(ae$value, "AEDECODIS", fixed=TRUE)
  lab <- application_generate_source(ws, "z_lab_change_over_time")
  testthat::expect_true(lab$passed)
  testthat::expect_match(lab$value, "proc means", fixed=TRUE)
  testthat::expect_match(lab$value, "CHG", fixed=TRUE)
  testthat::expect_match(lab$value, "resolved_digits", fixed=TRUE)
})

testthat::test_that("FDA-style source preserves section ordering and batch identity", {
  bytes <- readBin(file.path(project_root, "test", "fixtures", "demo_metadata.zip"), "raw",
                   n = file.info(file.path(project_root, "test", "fixtures", "demo_metadata.zip"))$size)
  ws <- application_import_bundle(new_empty_workspace(), bytes)$workspace
  result <- application_generate_source(ws, "z_lab_change_over_time")
  testthat::expect_true(result$passed)
  source <- result$value
  testthat::expect_lt(regexpr("Select the table population", source, fixed=TRUE),
                      regexpr("Discover hierarchical level 1 nodes", source, fixed=TRUE))
  testthat::expect_lt(regexpr("proc means", source, fixed=TRUE),
                      regexpr("data _TFL_REND_001", source, fixed=TRUE))
  testthat::expect_match(source, "data _TFL_HSTAT_001;", fixed=TRUE)
  testthat::expect_match(source, "group_path", fixed=TRUE)
  testthat::expect_match(source, "runtime_row_id", fixed=TRUE)
})

testthat::test_that("generated source has a canonical section manifest", {
  bytes <- readBin(file.path(project_root, "test", "fixtures", "demo_metadata.zip"), "raw",
                   n = file.info(file.path(project_root, "test", "fixtures", "demo_metadata.zip"))$size)
  ws <- application_import_bundle(new_empty_workspace(), bytes)$workspace
  result <- application_generate_source(ws, "baseline_characteristics")
  testthat::expect_true(result$passed)
  source <- result$value
  markers <- c("/* Select the table population. */", "/* Derive header column membership. */",
               "/* Assemble header membership. */", "/* Filter continuous chunk source before merge. */",
               "/* Analyze compatible continuous chunks once. */", "/* Render long-form statistics into independent row/header cells. */",
               "/* Assemble table rows and cells in template order. */")
  positions <- vapply(markers, function(marker) regexpr(marker, source, fixed=TRUE)[[1L]], integer(1))
  testthat::expect_true(all(positions > 0L))
  testthat::expect_true(all(diff(positions) > 0L))
})
