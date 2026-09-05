# Code-owned chunk type definitions. User metadata can select a registered type
# but cannot provide handlers or executable code.

registry_allowed_capabilities <- c("primitive", "container")
registry_allowed_grains <- c("subject", "record", "observation", "group")
registry_allowed_counting_units <- c("record", "distinct_subject", "distinct_key")

new_chunk_type_definition <- function(
    type_id,
    capability,
    required_fields,
    optional_fields,
    field_types,
    row_contract,
    data_grain,
    source_contract,
    merge_contract,
    analysis_contract,
    render_contract,
    correctness_guards,
    batch_contract,
    emitter = NULL) {
  if (!is.character(type_id) || length(type_id) != 1L || !nzchar(type_id)) {
    stop("Chunk type_id must be a non-empty string.", call. = FALSE)
  }
  if (!is.character(capability) || length(capability) != 1L ||
      !capability %in% registry_allowed_capabilities) {
    stop("Chunk capability is invalid.", call. = FALSE)
  }
  if (!is.character(required_fields) || !is.character(optional_fields)) {
    stop("Chunk field declarations must be character vectors.", call. = FALSE)
  }
  if (anyDuplicated(c(required_fields, optional_fields)) ||
      any(required_fields %in% optional_fields)) {
    stop("Chunk required and optional fields must be disjoint.", call. = FALSE)
  }
  if (!is.list(field_types) || is.null(names(field_types))) {
    stop("Chunk field_types must be a named list.", call. = FALSE)
  }
  if (!all(c(required_fields, optional_fields) %in% names(field_types))) {
    stop("Every declared chunk field needs a field type.", call. = FALSE)
  }
  if (!is.list(row_contract) || !is.list(source_contract) ||
      !is.list(merge_contract) || !is.list(analysis_contract) ||
      !is.list(render_contract) || !is.list(batch_contract)) {
    stop("Chunk contracts must be lists.", call. = FALSE)
  }
  if (!is.null(emitter) && !is.function(emitter)) {
    stop("Chunk emitter must be NULL or a function.", call. = FALSE)
  }
  structure(
    list(
      type_id = type_id,
      capability = capability,
      required_fields = required_fields,
      optional_fields = optional_fields,
      field_types = field_types,
      row_contract = row_contract,
      data_grain = data_grain,
      source_contract = source_contract,
      merge_contract = merge_contract,
      analysis_contract = analysis_contract,
      render_contract = render_contract,
      correctness_guards = correctness_guards,
      batch_contract = batch_contract,
      emitter = emitter
    ),
    class = c("ChunkTypeDefinition", "list")
  )
}

new_chunk_registry <- function(definitions) {
  if (!is.list(definitions) || length(definitions) == 0L) {
    stop("Chunk registry requires at least one definition.", call. = FALSE)
  }
  if (is.null(names(definitions)) || any(!nzchar(names(definitions)))) {
    stop("Chunk registry definitions must be named.", call. = FALSE)
  }
  ids <- vapply(definitions, function(definition) {
    if (!inherits(definition, "ChunkTypeDefinition")) {
      stop("Every registry definition must be a ChunkTypeDefinition.", call. = FALSE)
    }
    definition$type_id
  }, character(1L))
  if (anyDuplicated(unname(ids)) || !identical(unname(ids), names(definitions))) {
    stop("Chunk registry type IDs must be unique and match definition names.", call. = FALSE)
  }
  structure(list(definitions = definitions), class = c("ChunkRegistry", "list"))
}

chunk_registry_lookup <- function(registry, type_id) {
  if (!inherits(registry, "ChunkRegistry")) {
    stop("registry must be a ChunkRegistry.", call. = FALSE)
  }
  if (!is.character(type_id) || length(type_id) != 1L) {
    return(NULL)
  }
  registry$definitions[[type_id]]
}

chunk_registry_types <- function(registry) {
  if (!inherits(registry, "ChunkRegistry")) {
    stop("registry must be a ChunkRegistry.", call. = FALSE)
  }
  names(registry$definitions)
}

make_primitive_row_contract <- function(statistic_ids, require_condition = FALSE,
                                        allow_condition = require_condition) {
  list(
    types = c("label", "analysis"),
    common_fields = c("id", "type", "label", "indent_level"),
    analysis_fields = c("condition", "statistics", "cell_format"),
    required_analysis_fields = c("statistics", "cell_format",
                                 if (require_condition) "condition" else character()),
    allow_condition = isTRUE(allow_condition),
    statistic_ids = statistic_ids
  )
}

make_primitive_definition <- function(type_id, analysis_contract, statistic_ids,
                                      required_fields, optional_fields,
                                      require_condition = FALSE,
                                      batch_type = type_id) {
  new_chunk_type_definition(
    type_id = type_id,
    capability = "primitive",
    required_fields = required_fields,
    optional_fields = optional_fields,
    field_types = c(
      list(id = "string", type = "string", source_data = "non_empty_string",
           rows = "sequence", filter = "optional_string"),
      if (identical(type_id, "continuous_summary")) {
        list(analysis_variable = "string")
      } else {
        list(denominator = "mapping")
      }
    ),
    row_contract = make_primitive_row_contract(
      statistic_ids = statistic_ids,
      require_condition = require_condition,
      allow_condition = require_condition
    ),
    data_grain = "subject",
    source_contract = list(
      subject_key = "USUBJID",
      max_records_per_subject_after_filter = 1L
    ),
    merge_contract = list(
      key = "USUBJID",
      unit = "subject",
      cardinality = "one_filtered_source_record_per_subject",
      missing_source = "retain_scaffold"
    ),
    analysis_contract = analysis_contract,
    render_contract = list(
      result = "ChunkStatisticValue",
      cell = "ChunkRenderResult",
      placeholder_strategy = "TRANWRD"
    ),
    correctness_guards = c("duplicate_subject_key", "scaffold_membership"),
    batch_contract = list(
      batchable = TRUE,
      batch_type = batch_type,
      compatibility_fields = c("data_grain", "merge_contract", "analysis_contract")
    )
  )
}

default_chunk_registry <- local({
  registry <- NULL
  function() {
    if (!is.null(registry)) {
      return(registry)
    }
    continuous <- make_primitive_definition(
      type_id = "continuous_summary",
      statistic_ids = c("n", "mean", "sd", "median", "q1", "q3", "min", "max"),
      required_fields = c("id", "type", "source_data", "analysis_variable", "rows"),
      optional_fields = c("filter"),
      analysis_contract = list(
        statistics = c("n", "mean", "sd", "median", "q1", "q3", "min", "max"),
        procedure = "PROC MEANS",
        percentile_definition = "sas_default",
        standard_deviation = "sample"
      ),
      batch_type = "continuous"
    )
    continuous$emitter <- continuous_summary_emitter
    categorical <- make_primitive_definition(
      type_id = "categorical_summary_nonexclusive",
      statistic_ids = c("n", "pct"),
      required_fields = c("id", "type", "source_data", "denominator", "rows"),
      optional_fields = c("filter"),
      require_condition = TRUE,
      analysis_contract = list(
        statistics = c("n", "pct"),
        procedure = "PROC FREQ",
        percentage_scale = 100,
        row_overlap = "allowed"
      ),
      batch_type = "categorical_nonexclusive"
    )
    categorical$emitter <- categorical_summary_nonexclusive_emitter
    exclusive <- make_primitive_definition(
      type_id = "categorical_summary_exclusive",
      statistic_ids = c("n", "pct"),
      required_fields = c("id", "type", "source_data", "denominator", "rows"),
      optional_fields = c("filter"),
      require_condition = TRUE,
      analysis_contract = list(
        statistics = c("n", "pct"),
        procedure = "PROC FREQ",
        percentage_scale = 100,
        row_overlap = "warning"
      ),
      batch_type = "categorical_exclusive"
    )
    exclusive$emitter <- categorical_summary_exclusive_emitter
    hierarchical <- new_chunk_type_definition(
      type_id = "hierarchical_summary",
      capability = "container",
      required_fields = c("id", "type", "source_data", "source_contract",
                          "levels", "analysis_blocks"),
      optional_fields = c("filter"),
      field_types = list(
        id = "string", type = "string", source_data = "non_empty_string",
        source_contract = "mapping", levels = "sequence",
        analysis_blocks = "sequence", filter = "optional_string"
      ),
      row_contract = list(
        types = c("label", "analysis"),
        common_fields = c("id", "type", "label", "indent_level")
      ),
      data_grain = "group",
      source_contract = list(
        grains = c("subject", "record", "observation"),
        duplicate_policy = "error"
      ),
      merge_contract = list(
        broadcast_key = "subject_key",
        dynamic_nodes = "union_of_eligible_sources"
      ),
      analysis_contract = list(
        nested_types = c("continuous_summary", "categorical_summary_nonexclusive",
                         "categorical_summary_exclusive"),
        cross_container_batch = FALSE
      ),
      render_contract = list(
        result = "HierarchicalAnalysisResult",
        row = "HierarchicalRenderRow",
        static_before_dynamic = TRUE
      ),
      correctness_guards = c("duplicate_record_key", "level_order", "anchor_reference"),
      batch_contract = list(
        batchable = FALSE,
        batch_type = "hierarchical",
        compatibility_fields = character()
      )
    )
    registry <<- new_chunk_registry(list(
      continuous_summary = continuous,
      categorical_summary_nonexclusive = categorical,
      categorical_summary_exclusive = exclusive,
      hierarchical_summary = hierarchical
    ))
    registry
  }
})
