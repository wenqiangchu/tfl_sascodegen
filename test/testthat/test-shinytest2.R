testthat::expect_true(requireNamespace("shinytest2", quietly = TRUE))
testthat::expect_true(requireNamespace("chromote", quietly = TRUE))
Sys.setenv(NOT_CRAN = "true")
chromote::set_chrome_args(c("--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"))

new_editor_app <- function(name) {
  shinytest2::AppDriver$new(app_dir=project_root,name=name,height=900,width=1400,
                            variant="local",load_timeout=30000)
}

import_demo <- function(app) {
  app$upload_file(bundle=file.path(project_root,"test","fixtures","demo_metadata.zip"))
  app$wait_for_idle(1200)
}

select_list_row <- function(app, type, row) {
  app$click(selector=sprintf("#%s_list table tbody tr:nth-child(%d) td:first-child",type,row))
  app$wait_for_idle(500)
}

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
  app$set_inputs(chunk_1_subject_key="SUBJID");app$click("template_save");app$wait_for_idle(500)
  testthat::expect_match(app$get_value(input="chunk_1_subject_key"),"SUBJID",fixed=TRUE)
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
  testthat::expect_match(source, "_TFL_HSTAT_", fixed = TRUE)
  testthat::expect_match(source, "SOC", fixed = TRUE)
  testthat::expect_match(source, "PT", fixed = TRUE)
})
