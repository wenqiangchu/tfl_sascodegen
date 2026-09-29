metadata_editor_ui <- function() {
  object_list_box <- function(title, type) {
    box(title = title, width = 4,
        actionButton(paste0(type, "_new"), "New"),
        actionButton(paste0(type, "_delete"), "Delete"),
        DTOutput(paste0(type, "_list")))
  }
  dashboardPage(
    dashboardHeader(title = "SAS Code Generator",
      tags$li(class="dropdown", style="display:flex;gap:6px;align-items:center;padding:7px 15px;",
        actionButton("upload_metadata", "Upload metadata", class = "btn btn-default btn-sm",
          style = "width:180px;height:30px;padding:5px 10px;line-height:18px;font-size:12px;color:#333;background-color:#fff;border-color:#ccc;"),
        uiOutput("download_metadata_ui"),
        downloadButton("download_demo_package", "Download demo package", class = "btn btn-default btn-sm",
          style = "width:180px;height:30px;padding:5px 10px;line-height:18px;font-size:12px;color:#333;background-color:#fff;border-color:#ccc;")
      )),
    dashboardSidebar(
      sidebarMenu(id = "main_nav",
        menuItem("Metadata", tabName = "metadata", icon = icon("database")),
        menuItem("Table Metadata", tabName = "table_metadata", icon = icon("table")),
        menuItem("Template Editor", tabName = "template_editor", icon = icon("file")),
        menuItem("Generate SAS", tabName = "generate_sas", icon = icon("code")))),
    dashboardBody(
      tags$head(
        tags$meta(name="viewport", content="width=device-width, initial-scale=1, shrink-to-fit=no"),
        tags$script(HTML("
          Shiny.addCustomMessageHandler('metadata-loaded', function(message) {
            var loaded = message.loaded === true;
            document.getElementById('metadata_gate').style.display = loaded ? 'none' : '';
            document.getElementById('metadata_content').style.display = loaded ? '' : 'none';
          });
        ")),
        tags$style(HTML("\n          /* Keep chunk title actions at the far right of the box header.\n             shinydashboard renders box(title=...) inside h3.box-title, whose\n             default float layout otherwise places nested controls at the left. */\n          .chunk-card .box-header .box-title,\n          [id^='chunk-card-'] .box-header .box-title {\n            display: flex !important;\n            align-items: center !important;\n            width: 100% !important;\n            float: none !important;\n            overflow: visible !important;\n          }\n          .chunk-titlebar {\n            display: flex !important;\n            align-items: center !important;\n            width: 100% !important;\n            min-width: 0;\n          }\n          .chunk-title-text {\n            flex: 0 1 auto !important;\n            min-width: 0;\n          }\n          .chunk-title-actions {\n            display: flex !important;\n            align-items: center !important;\n            gap: 4px !important;\n            margin-left: auto !important;\n            float: none !important;\n            flex: 0 0 auto !important;\n          }\n          .chunk-title-actions .btn {\n            float: none !important;\n            margin-top: 0 !important;\n          }\n          @media (max-width: 767px) {\n            .content-wrapper, .right-side { overflow-x: hidden; }\n            .box-header .box-title { white-space: normal; }\n            .navbar-custom-menu > .navbar-nav > li { float: none; }\n          }\n        "))
      ),
      tags$style(HTML(".chunk-titlebar { position: relative !important; display: block !important; width: 100% !important; min-width: 0 !important; padding-right: 260px !important; } .chunk-title-text { display: block !important; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; } .chunk-title-actions { position: absolute !important; top: 50% !important; right: 0 !important; transform: translateY(-50%) !important; display: flex !important; align-items: center !important; gap: 4px !important; white-space: nowrap !important; } .chunk-title-actions .btn { float: none !important; margin-top: 0 !important; } @media (max-width: 767px) { .chunk-titlebar { padding-right: 0 !important; padding-bottom: 38px !important; } .chunk-title-text { white-space: normal !important; } .chunk-title-actions { top: auto !important; right: auto !important; left: 0 !important; bottom: 0 !important; transform: none !important; } }")),
      tags$div(id = "metadata_gate",
        box(width = 12, status = "info", solidHeader = TRUE,
          title = "Upload metadata to begin",
          p("Upload a metadata ZIP bundle to start editing."),
          actionButton("upload_metadata_gate", "Upload metadata"))),
      # The initial HTML must be correct before any Shiny connection or output.
      tags$div(id="metadata_content", style="display:none;", tabItems(
      tabItem(tabName = "metadata",
        tabsetPanel(id = "metadata_panel",
          tabPanel("Population", value = "population", fluidRow(
            object_list_box("Populations", "population"),
            box(title = "Population metadata", width = 8, status = "primary", solidHeader = TRUE,
              uiOutput("population_id_ui"), textInput("population_label", "Label"),
              textAreaInput("population_expression", "SAS expression", rows = 3),
              actionButton("population_save", "Save"),
              actionButton("population_discard", "Discard changes")))),
          tabPanel("Header", value = "header", fluidRow(
            object_list_box("Headers", "header"),
            box(title = "Header metadata", width = 8, status = "primary", solidHeader = TRUE,
              uiOutput("header_id_ui"), textInput("header_source_data", "Source data"),
              selectInput("header_orientation", "Page orientation",
                          choices = c("Select orientation" = "", "Portrait" = "portrait",
                                      "Landscape" = "landscape"), selected = ""),
              h4("Columns and spanning headers"),
              actionButton("header_column_new", "Add row"),
              actionButton("header_column_delete", "Delete selected row"),
              DTOutput("header_columns_table"), actionButton("header_save", "Save"),
              actionButton("header_discard", "Discard changes")))))),
      tabItem(tabName = "table_metadata", fluidRow(
        object_list_box("Tables", "table"),
        box(title = "Table metadata", width = 8, status = "primary", solidHeader = TRUE,
          uiOutput("table_id_ui"), selectInput("table_population_id", "Population", character()),
          selectInput("table_header_id", "Header", character()),
          selectInput("table_template_id", "Template", character()),
          textAreaInput("table_custom_before", "Custom code before", rows = 4),
          textAreaInput("table_custom_after", "Custom code after", rows = 4),
          actionButton("table_save", "Save"), actionButton("table_discard", "Discard changes")))),
      tabItem(tabName = "template_editor", fluidRow(
        object_list_box("Templates", "template"),
        box(title = "Template metadata", width = 8, status = "primary", solidHeader = TRUE,
          uiOutput("template_id_ui"), textInput("template_stub_header", "Stub header"),
          actionButton("template_save", "Save"), actionButton("template_discard", "Discard changes"),
          actionButton("chunk_add", "Add chunk"), uiOutput("chunk_cards")))),
      tabItem(tabName = "generate_sas",
        box(title = "Generate SAS", width = 12, status = "success", solidHeader = TRUE,
          selectInput("generate_table", "Table", character()),
          checkboxInput("generate_duplicate_check", "Include duplicate record checks", value = TRUE),
          radioButtons("generate_output_mode", "Output mode",
                       choices = c("Source report (PROC REPORT)" = "report",
                                    "QC compare (PROC COMPARE)" = "compare"),
                       selected = "report", inline = TRUE),
          conditionalPanel("input.generate_output_mode == 'compare'",
            helpText("QC compares with tables.<table_id>. Prepare that source dataset before running the SAS program.")),
          actionButton("generate", "Generate SAS", icon = icon("play")),
          uiOutput("download_sas_ui"),
          verbatimTextOutput("status"), verbatimTextOutput("source")))
      ))
    )
  )
}
