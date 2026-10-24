testthat::expect_true(requireNamespace("shinytest2", quietly = TRUE))
testthat::expect_true(requireNamespace("chromote", quietly = TRUE))
Sys.setenv(NOT_CRAN = "true")
chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))

new_editor_app <- function(name) {
  shinytest2::AppDriver$new(app_dir=project_root,name=name,height=900,width=1400,
                            variant="local",load_timeout=30000)
}

# Upload models render the file input inside a modal, so opening the modal and
# selecting the file must wait for that render separately. Clicking and
# uploading back to back races the modal render and intermittently fails with
# "Cannot find HTML element with selector #bundle.shiny-bound-input".
open_upload_dialog <- function(app, button = "upload_metadata") {
  app$click(button)
  app$wait_for_idle(300)
  app$wait_for_js("document.querySelector('#bundle.shiny-bound-input') !== null", timeout = 10000)
  invisible(app)
}

import_demo <- function(app) {
  open_upload_dialog(app)
  app$upload_file(bundle=file.path(project_root,"assets","demo_metadata.zip"))
  app$click("confirm_import")
  app$wait_for_idle(1200)
}

select_list_row <- function(app, type, row) {
  app$click(selector=sprintf("#%s_list table tbody tr:nth-child(%d) td:first-child",type,row))
  app$wait_for_idle(500)
}

visible_dashboard_panes <- function(app) {
  app$get_js(paste0(
    "Array.from(document.querySelectorAll('",
    "#shiny-tab-metadata,#shiny-tab-table_metadata,",
    "#shiny-tab-template_editor,#shiny-tab-generate_sas')).",
    "filter(function(x) { return getComputedStyle(x).display !== 'none'; }).",
    "map(function(x) { return x.id; })"
  ))
}

testthat::test_that("dashboard navigation displays exactly one top-level pane", {
  app <- new_editor_app("editor-navigation")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)

  panes <- c("metadata", "table_metadata", "template_editor", "generate_sas")
  for (pane in panes) {
    app$set_inputs(main_nav = pane)
    app$wait_for_idle(500)
    testthat::expect_identical(
      unlist(visible_dashboard_panes(app), use.names = FALSE),
      paste0("shiny-tab-", pane)
    )
  }
})

testthat::test_that("first import and clean switching do not show a dirty guard", {
  app<-new_editor_app("editor-clean");on.exit(app$stop(),add=TRUE);import_demo(app)
  testthat::expect_false(grepl("Unsaved changes",app$get_html("body"),fixed=TRUE))
  testthat::expect_match(app$get_value(input="population_label"),"FAS",fixed=TRUE)
  select_list_row(app,"population",2)
  testthat::expect_match(app$get_value(input="population_label"),"SAFETY",fixed=TRUE)
  testthat::expect_false(grepl("Unsaved changes",app$get_html("body"),fixed=TRUE))
})

testthat::test_that("dirty switch supports cancel discard and restored-clean comparison", {
  app<-new_editor_app("editor-guard");on.exit(app$stop(),add=TRUE);import_demo(app)
  app$set_inputs(population_label="FAS edited");select_list_row(app,"population",2)
  testthat::expect_match(app$get_html("body"),"Unsaved changes",fixed=TRUE)
  app$click("guard_cancel");app$wait_for_idle(300)
  testthat::expect_equal(app$get_value(input="population_label"),"FAS edited")
  select_list_row(app,"population",2);app$click("guard_discard");app$wait_for_idle(500)
  testthat::expect_equal(app$get_value(input="population_label"),"SAFETY")
  select_list_row(app,"population",1);app$set_inputs(population_label="changed");app$set_inputs(population_label="FAS")
  select_list_row(app,"population",2)
  testthat::expect_false(grepl("Unsaved changes",app$get_html("body"),fixed=TRUE))
})

testthat::test_that("new ID lifecycle supports cancel duplicate save and discard", {
  app<-new_editor_app("editor-new");on.exit(app$stop(),add=TRUE);import_demo(app)
  app$click("population_new");testthat::expect_match(app$get_html("body"),"New Population",fixed=TRUE)
  app$click("cancel_new_object");testthat::expect_false(grepl("new_population",app$get_html("#population_list"),fixed=TRUE))
  app$click("population_new");app$set_inputs(new_object_id="fas");app$click("confirm_new_object")
  testthat::expect_match(app$get_html("body"),"ID already exists",fixed=TRUE)
  app$set_inputs(new_object_id="new_population");app$click("confirm_new_object");app$wait_for_idle(500)
  testthat::expect_match(app$get_html("#population_list"),"new_population",fixed=TRUE)
  app$click("population_discard");app$wait_for_idle(400)
  testthat::expect_false(grepl("new_population",app$get_html("#population_list"),fixed=TRUE))
  app$click("population_new");app$set_inputs(new_object_id="saved_population");app$click("confirm_new_object")
  app$set_inputs(population_label="Saved population");app$click("population_save");app$wait_for_idle(500)
  testthat::expect_match(app$get_html("#population_list"),"saved_population",fixed=TRUE)
})

testthat::test_that("delete is immediate after confirmation and referenced values are blocked", {
  app<-new_editor_app("editor-delete");on.exit(app$stop(),add=TRUE);import_demo(app)
  select_list_row(app,"population",3);app$click("population_delete");app$wait_for_idle(300)
  testthat::expect_match(app$get_html("body"),"Confirm delete",fixed=TRUE)
  app$click("confirm_delete");app$wait_for_idle(500)
  testthat::expect_false(grepl("exploratory",app$get_html("#population_list"),fixed=TRUE))
  select_list_row(app,"population",1);app$click("population_delete");app$wait_for_idle(300)
  testthat::expect_match(app$get_html("body"),"referenced",ignore.case=TRUE)
})

testthat::test_that("header rows and template cards expose structural editing", {
  app<-new_editor_app("editor-structures");on.exit(app$stop(),add=TRUE);import_demo(app)
  app$set_inputs(metadata_panel="header");app$wait_for_idle(600)
  app$click("header_column_new");app$wait_for_idle(300)
  testthat::expect_match(app$get_html("#header_columns_table"),"column_002",fixed=TRUE)
  app$click("header_discard");app$wait_for_idle(400)
  app$set_inputs(main_nav="template_editor");app$wait_for_idle(700)
  testthat::expect_match(app$get_html("#chunk_cards"),"hierarchical_summary",fixed=TRUE)
  testthat::expect_match(app$get_html("#chunk_cards"),'readonly="readonly"',fixed=TRUE)
  testthat::expect_false(grepl("UI identity:", app$get_html("#chunk_cards"), fixed=TRUE))
  testthat::expect_match(app$get_html("#chunk_cards"), "chunk_1_delete", fixed=TRUE)
  testthat::expect_match(app$get_html("#chunk_cards"), "chunk_1_up", fixed=TRUE)
  testthat::expect_match(app$get_html("#chunk_cards"), "chunk_1_down", fixed=TRUE)
  app$set_inputs(chunk_1_subject_key="SUBJID");app$click("template_save");app$wait_for_idle(500)
  testthat::expect_match(app$get_value(input="chunk_1_subject_key"),"SUBJID",fixed=TRUE)
})

testthat::test_that("Add chunk selects each supported type before creation", {
  app <- new_editor_app("editor-chunk-types")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(main_nav = "template_editor")
  app$wait_for_idle(700)

  types <- c(
    continuous_summary = "continuous_summary",
    categorical_summary_nonexclusive = "categorical_summary_nonexclusive",
    categorical_summary_exclusive = "categorical_summary_exclusive",
    hierarchical_summary = "hierarchical_summary"
  )
  for (type in unname(types)) {
    app$click("chunk_add")
    app$wait_for_idle(200)
    testthat::expect_match(app$get_html("body"), "Add chunk", fixed = TRUE)
    app$set_inputs(new_chunk_type = type)
    app$click("confirm_new_chunk")
    app$wait_for_idle(500)
  }
  html <- app$get_html("#chunk_cards")
  for (type in unname(types)) testthat::expect_match(html, type, fixed = TRUE)
})

testthat::test_that("chunk move buttons reorder cards and remain usable", {
  app <- new_editor_app("editor-chunk-move")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(main_nav = "template_editor")
  app$wait_for_idle(700)
  app$click("chunk_add")
  app$wait_for_idle(200)
  app$set_inputs(new_chunk_type = "continuous_summary")
  app$click("confirm_new_chunk")
  app$wait_for_idle(600)
  chunk_types <- function() unlist(app$get_js("Array.from(document.querySelectorAll('#chunk_cards input[id$=_type]')).map(function(x){return x.value})"), use.names = FALSE)
  types_before <- chunk_types()
  testthat::expect_length(types_before, 2)
  app$click("chunk_2_up")
  app$wait_for_idle(600)
  testthat::expect_identical(chunk_types(), rev(types_before))
  app$click("chunk_1_down")
  app$wait_for_idle(600)
  types_after_down <- chunk_types()
  testthat::expect_identical(types_after_down, types_before)
  app$click("chunk_2_up")
  app$wait_for_idle(600)
  testthat::expect_identical(chunk_types(), rev(types_before))
})

testthat::test_that("hierarchical block rows use DT controls and structural actions", {
  app <- new_editor_app("editor-hierarchical-dt")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(main_nav = "template_editor")
  app$wait_for_idle(700)
  select_list_row(app, "template", 1)
  testthat::expect_match(app$get_html("#chunk_cards"), "analysis_blocks", fixed = TRUE)
  testthat::expect_match(app$get_html("#chunk_cards"), "chunk_1_block_1_rows", fixed = TRUE)
  row_count <- function() unlist(app$get_js("document.querySelectorAll('#chunk_1_block_1_rows tbody tr').length"), use.names=FALSE)
  testthat::expect_equal(row_count(), 2)
  testthat::expect_false(grepl("statistic_new", app$get_html("#chunk_cards"), fixed=TRUE))
  app$set_inputs(chunk_1_block_1_rows_cell_edit=list(row=1,col=1,value="Edited severity"))
  app$set_inputs(chunk_1_block_1_rows_cell_edit=list(row=1,col=4,value="n pct"))
  app$set_inputs(chunk_1_block_1_rows_cell_edit=list(row=1,col=5,value="- 1"))
  app$wait_for_idle(300)
  app$click("chunk_1_block_1_row_new")
  app$wait_for_idle(500)
  testthat::expect_equal(row_count(), 3)
  testthat::expect_match(app$get_html("#chunk_1_block_1_rows"), "Statistics", fixed=TRUE)
  testthat::expect_match(app$get_html("#chunk_1_block_1_rows"), "Digits", fixed=TRUE)
})

testthat::test_that("template row tables stay bound to their chunk and clean AE navigation is unguarded", {
  app <- new_editor_app("editor-template-row-binding")
  on.exit(app$stop(), add=TRUE)
  import_demo(app)
  app$set_inputs(main_nav="template_editor"); app$wait_for_idle(700)
  testthat::expect_match(app$get_html("#chunk_1_block_1_rows"), "Mild", fixed=TRUE)
  app$set_inputs(main_nav="table_metadata"); app$wait_for_idle(500)
  testthat::expect_false(grepl("Unsaved changes",app$get_html("body"),fixed=TRUE))
  app$set_inputs(main_nav="template_editor"); app$wait_for_idle(500)
  select_list_row(app,"template",2)
  testthat::expect_match(app$get_html("#chunk_1_rows"), "Age (years)", fixed=TRUE)
  testthat::expect_false(grepl("Female",app$get_html("#chunk_1_rows"),fixed=TRUE))
  testthat::expect_match(app$get_html("#chunk_2_rows"), "- 1", fixed=TRUE)
})

testthat::test_that("generate is guarded and produces a source preview", {
  app<-new_editor_app("editor-generate");on.exit(app$stop(),add=TRUE);import_demo(app)
  app$set_inputs(population_label="dirty");app$set_inputs(main_nav="generate_sas");app$wait_for_idle(400)
  testthat::expect_match(app$get_html("body"),"Unsaved changes",fixed=TRUE)
  app$click("guard_cancel");app$wait_for_idle(300)
  app$set_inputs(population_label="FAS");app$set_inputs(main_nav="generate_sas");app$wait_for_idle(400)
  app$set_inputs(generate_table="baseline_characteristics")
  app$click("generate");app$wait_for_idle(800)
  testthat::expect_match(app$get_html("#source"),"DATA",ignore.case=TRUE)
})

testthat::test_that("SAS download is only enabled for the current successful generation", {
  app <- new_editor_app("editor-download-state")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(main_nav = "generate_sas")
  app$wait_for_idle(500)
  testthat::expect_match(app$get_html("#download_sas_ui"), "download_sas_disabled", fixed = TRUE)
  app$set_inputs(generate_table = "baseline_characteristics")
  app$click("generate")
  app$wait_for_idle(800)
  testthat::expect_false(grepl("download_sas_disabled", app$get_html("#download_sas_ui"), fixed = TRUE))
  testthat::expect_true(app$get_value(input = "generate_duplicate_check"))
  testthat::expect_identical(app$get_value(input = "generate_output_mode"), "report")
  testthat::expect_match(app$get_text("#source"), "WARNING: [USER] duplicate_key", fixed = TRUE)

  app$set_inputs(generate_duplicate_check = FALSE)
  app$wait_for_idle(300)
  testthat::expect_match(app$get_html("#download_sas_ui"), "download_sas_disabled", fixed = TRUE)
  testthat::expect_identical(app$get_text("#source"), "")
  app$click("generate")
  app$wait_for_idle(600)
  testthat::expect_false(grepl("duplicate_key", app$get_text("#source"), fixed = TRUE))
  testthat::expect_match(app$get_text("#source"), "proc report data=WORK._TFL_ASM_001", fixed = TRUE)

  app$set_inputs(generate_output_mode = "compare")
  app$wait_for_idle(300)
  testthat::expect_match(app$get_html("#download_sas_ui"), "download_sas_disabled", fixed = TRUE)
  app$click("generate")
  app$wait_for_idle(600)
  testthat::expect_match(app$get_text("#source"),
                         "proc compare base=tables.baseline_characteristics compare=WORK._TFL_ASM_001 listvar;",
                         fixed = TRUE)
  testthat::expect_false(grepl("proc report|ods rtf", app$get_text("#source"), ignore.case = TRUE))
  testthat::expect_false(grepl("download_sas_disabled", app$get_html("#download_sas_ui"), fixed = TRUE))

  app$set_inputs(generate_table = "ae_by_soc_pt")
  app$wait_for_idle(300)
  testthat::expect_match(app$get_html("#download_sas_ui"), "download_sas_disabled", fixed = TRUE)
})

testthat::test_that("AE hierarchical table generates a complete SAS source preview", {
  app <- new_editor_app("editor-ae-generate")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(main_nav = "generate_sas")
  app$wait_for_idle(500)
  app$set_inputs(generate_table = "ae_by_soc_pt", wait_ = FALSE)
  app$wait_for_idle(1000)
  app$click("generate")
  app$wait_for_idle(1200)
  testthat::expect_match(app$get_text("#status"), "SAS source generated", fixed = TRUE)
  source <- app$get_text("#source")
  testthat::expect_gt(nchar(source), 1000)
  testthat::expect_match(source, "Filter and guard hierarchical", fixed = TRUE)
  testthat::expect_match(source, "Execute nested primitive analysis", fixed = TRUE)
  testthat::expect_match(source, "_TFL_HFLAT_", fixed = TRUE)
  testthat::expect_match(source, "proc report data=WORK._TFL_ASM_001", fixed = TRUE)
  testthat::expect_match(source, "hierarchy_level ne previous_level", fixed = TRUE)
  testthat::expect_match(source, "SOC", fixed = TRUE)
  testthat::expect_match(source, "PT", fixed = TRUE)
})

testthat::test_that("Header orientation saves, discards, and controls the generated page", {
  app <- new_editor_app("editor-header-orientation")
  on.exit(app$stop(), add = TRUE)
  import_demo(app)
  app$set_inputs(metadata_panel = "header")
  app$wait_for_idle(500)
  select_list_row(app, "header", 1)
  testthat::expect_identical(app$get_value(input = "header_orientation"), "portrait")
  app$set_inputs(header_orientation = "landscape")
  app$click("header_save")
  app$wait_for_idle(500)
  select_list_row(app, "header", 2)
  select_list_row(app, "header", 1)
  testthat::expect_identical(app$get_value(input = "header_orientation"), "landscape")
  app$set_inputs(header_orientation = "portrait")
  app$click("header_discard")
  app$wait_for_idle(500)
  testthat::expect_identical(app$get_value(input = "header_orientation"), "landscape")
  app$set_inputs(main_nav = "generate_sas", generate_table = "baseline_characteristics")
  app$wait_for_idle(500)
  app$click("generate")
  app$wait_for_idle(1000)
  testthat::expect_match(app$get_text("#source"), "papersize=letter orientation=landscape", fixed = TRUE)
})
