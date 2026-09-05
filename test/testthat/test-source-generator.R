generator_fixture <- function() {
  new_metadata_bundle(
    populations = list(list(id = "safety", label = "Safety", expression = "SAFFL = 'Y'")),
    headers = list(list(
      id = "treatment", source_data = "&lib..&member",
      columns = list(
        list(id = "a", label = "A", condition = "TRT = 'A'", display_order = 1L,
             width = 1, alignment = "center"),
        list(id = "all", label = "Overall", condition = "1", display_order = 2L,
             width = 1, alignment = "center")
      )
    )),
    tables = list(list(
      id = "t1", population_id = "safety", header_id = "treatment",
      template_id = "demog",
      custom_code = list(before = "%let before=1;", after = "%put after;")
    )),
    templates = list(list(id = "demog", body = list(chunks = list(
      list(id = "age", type = "continuous_summary", source_data = "adam.adsl",
           analysis_variable = "AGE", rows = list(
             list(id = "r1", type = "analysis", label = "Mean",
                  statistics = list(list(id = "mean", digits = 1L)), cell_format = "{mean}")
           )),
      list(id = "weight", type = "continuous_summary", source_data = "&ADSL",
           analysis_variable = "WEIGHT", rows = list(
             list(id = "r1", type = "analysis", label = "N",
                  statistics = list(list(id = "n")), cell_format = "{n}")
           ))
    ))))
  )
}

mock_generator_registry <- function(log = NULL) {
  definitions <- default_chunk_registry()$definitions
  definitions$continuous_summary$emitter <- function(plan, resolved) {
    if (!is.null(log)) log$plans[[length(log$plans) + 1L]] <- plan
    text <- paste(
      "/* Filter and merge compatible chunks. */",
      paste0("data ", plan$input_dataset, "; set _TFL_MEM_001; run;"),
      "/* Analyze compatible chunks. */",
      paste0("proc means data=", plan$input_dataset, "; run;"),
      "/* Render chunk cells. */",
      paste0("data ", plan$render_dataset, "; stop; run;"), sep = "\n"
    )
    new_emitter_output(
      list(new_source_section("continuous_batch", "chunk", "continuous", 1L, text)),
      plan$statistic_dataset, plan$render_dataset
    )
  }
  new_chunk_registry(definitions)
}

testthat::test_that("generator resolves references and batches compatible chunks", {
  log <- new.env(parent = emptyenv())
  log$plans <- list()
  result <- generate_table_source(generator_fixture(), "t1", mock_generator_registry(log))
  testthat::expect_true(result$passed)
  testthat::expect_length(log$plans, 1L)
  testthat::expect_identical(log$plans[[1L]]$chunk_orders, c(1L, 2L))
  testthat::expect_identical(log$plans[[1L]]$input_dataset, "_TFL_CIN_001")
  testthat::expect_identical(log$plans[[1L]]$precision_dataset, "_TFL_CPREC_001")
  testthat::expect_identical(
    vapply(log$plans[[1L]]$logical_maps, `[[`, "", "chunk_id"),
    c("age", "weight")
  )
  testthat::expect_identical(
    log$plans[[1L]]$logical_maps[[1L]]$rows[[1L]]$statistic_ids,
    "mean"
  )
  testthat::expect_identical(lengths(regmatches(result$source,
    gregexpr("proc means", result$source, fixed = TRUE))), 1L)
})

testthat::test_that("source sections preserve custom code and opaque SAS references", {
  result <- generate_table_source(generator_fixture(), "t1", mock_generator_registry())
  testthat::expect_true(result$passed)
  testthat::expect_true(startsWith(result$source, "%let before=1;"))
  testthat::expect_true(endsWith(result$source, "%put after;"))
  testthat::expect_match(result$source, "set &lib..&member;", fixed = TRUE)
  testthat::expect_match(result$source, "SAFFL = 'Y'", fixed = TRUE)
  testthat::expect_match(result$source, "Derive header column membership", fixed = TRUE)
  testthat::expect_match(result$source, "Assemble table rows and cells", fixed = TRUE)
  testthat::expect_match(result$source, "mapped back through chunk/row/header identities",
                         fixed = TRUE)
  testthat::expect_false(grepl("provenance|binding_profile|manifest", result$source,
                              ignore.case = TRUE))
  repeated <- generate_table_source(generator_fixture(), "t1", mock_generator_registry())
  testthat::expect_identical(result$source, repeated$source)
})

testthat::test_that("prerequisite failures are ordered and return no partial source", {
  bundle <- generator_fixture()
  bundle$tables[[1L]]$population_id <- "missing_population"
  bundle$tables[[1L]]$header_id <- "missing_header"
  result <- generate_table_source(bundle, "t1", mock_generator_registry())
  testthat::expect_false(result$passed)
  testthat::expect_null(result$source)
  testthat::expect_identical(vapply(result$errors, `[[`, "", "code"),
                            rep("generation_reference_missing", 2L))
  testthat::expect_match(result$errors[[1L]]$path, "population_id", fixed = TRUE)
  testthat::expect_match(result$errors[[2L]]$path, "header_id", fixed = TRUE)

  missing_table <- generate_table_source(generator_fixture(), "unknown", mock_generator_registry())
  testthat::expect_identical(missing_table$errors[[1L]]$code, "generation_table_missing")
  testthat::expect_null(missing_table$source)

  missing_emitter <- generate_table_source(generator_fixture(), "t1")
  testthat::expect_false(missing_emitter$passed)
  testthat::expect_null(missing_emitter$source)
  testthat::expect_identical(missing_emitter$errors[[1L]]$code,
                            "generation_emitter_unavailable")
})

testthat::test_that("invalid emitter output is a generation contract failure", {
  definitions <- default_chunk_registry()$definitions
  definitions$continuous_summary$emitter <- function(plan, resolved) list(text = "partial")
  result <- generate_table_source(generator_fixture(), "t1", new_chunk_registry(definitions))
  testthat::expect_false(result$passed)
  testthat::expect_null(result$source)
  testthat::expect_identical(result$errors[[1L]]$code, "generation_contract_invalid")
})

testthat::test_that("duplicate emitter sections are rejected before assembly", {
  definitions <- default_chunk_registry()$definitions
  definitions$continuous_summary$emitter <- function(plan, resolved) {
    section <- new_source_section("duplicate", "chunk", "age", 1L, "data partial; run;")
    new_emitter_output(
      list(section, section), plan$statistic_dataset, plan$render_dataset
    )
  }
  result <- generate_table_source(generator_fixture(), "t1", new_chunk_registry(definitions))
  testthat::expect_false(result$passed)
  testthat::expect_null(result$source)
  testthat::expect_identical(result$errors[[1L]]$code, "generation_contract_invalid")
})
