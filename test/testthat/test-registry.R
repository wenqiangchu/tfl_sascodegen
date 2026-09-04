testthat::test_that("the built-in registry exposes the approved types", {
  registry <- default_chunk_registry()
  testthat::expect_s3_class(registry, "ChunkRegistry")
  testthat::expect_identical(
    chunk_registry_types(registry),
    c("continuous_summary", "categorical_summary_nonexclusive",
      "categorical_summary_exclusive", "hierarchical_summary")
  )
  continuous <- chunk_registry_lookup(registry, "continuous_summary")
  testthat::expect_identical(continuous$capability, "primitive")
  testthat::expect_true(continuous$batch_contract$batchable)
  testthat::expect_identical(continuous$analysis_contract$procedure, "PROC MEANS")
  hierarchical <- chunk_registry_lookup(registry, "hierarchical_summary")
  testthat::expect_identical(hierarchical$capability, "container")
  testthat::expect_false(hierarchical$batch_contract$batchable)
})

testthat::test_that("registry construction is all-or-nothing", {
  definition <- default_chunk_registry()$definitions$continuous_summary
  testthat::expect_error(
    new_chunk_registry(list(a = definition, b = definition)),
    "type IDs must be unique"
  )
  testthat::expect_error(
    new_chunk_type_definition(
      type_id = "bad", capability = "primitive", required_fields = "id",
      optional_fields = "id", field_types = list(id = "string"), row_contract = list(),
      data_grain = "subject", source_contract = list(), merge_contract = list(),
      analysis_contract = list(), render_contract = list(), correctness_guards = character(),
      batch_contract = list()
    ),
    "disjoint"
  )
})
