chunk_row_ui <- function(row,prefix,index) {
  p<-paste0(prefix,"row_",index,"_"); tags$div(class="well",
    readonly_editor_input(paste0(p,"id"),"Row ID",row$id),readonly_editor_input(paste0(p,"type"),"Row type",row$type),
    textInput(paste0(p,"label"),"Label",row$label %||% ""),numericInput(paste0(p,"indent"),"Indent",row$indent_level %||% 0,min=0),
    if(identical(row$type,"analysis")) tagList(if(!is.null(row$condition))textInput(paste0(p,"condition"),"Condition",row$condition),textInput(paste0(p,"cell_format"),"Cell format",row$cell_format %||% ""),
      tagList(lapply(seq_along(row$statistics %||% list()),function(s){stat<-row$statistics[[s]];sp<-paste0(p,"stat_",s,"_");tags$div(readonly_editor_input(paste0(sp,"id"),"Statistic",stat$id),textInput(paste0(sp,"digits"),"Digits",as.character(stat$digits %||% "")))}))))
}

chunk_field_row <- function(...) fluidRow(...)
chunk_field <- function(width = 4, content) column(width, content)

chunk_card_ui <- function(chunk,index) {
  p<-paste0("chunk_",index,"_"); uid <- chunk$ui_uid %||% sprintf("chunk_%06d", index)
  common<-tagList(
    chunk_field_row(
      chunk_field(4, readonly_editor_input(paste0(p,"id"),"ID",chunk$id)),
      chunk_field(4, readonly_editor_input(paste0(p,"type"),"Type",chunk$type))
    ),
    chunk_field_row(
      chunk_field(4, textInput(paste0(p,"source_data"),"Source data",chunk$source_data %||% "")),
      chunk_field(4, textInput(paste0(p,"filter"),"Filter",chunk$filter %||% ""))
    )
  )
  rows_ui <- tagList(h4("Rows / statistics"), collection_buttons(p,"row","rows"))
  # Primitive chunks declare their counting unit the same way hierarchical blocks
  # do, so one shared control keeps the two editors from drifting apart.
  counting_unit_ui <- chunk_field_row(
    chunk_field(4, selectInput(paste0(p,"counting_unit"),"Counting unit",
                               c("record","distinct_subject","distinct_key"),
                               selected = chunk$counting_unit %||% "distinct_subject")),
    chunk_field(8, textInput(paste0(p,"distinct_key"),"Distinct key",
                             paste(chunk$distinct_key %||% character(), collapse=", ")))
  )
  if(chunk$type=="continuous_summary") specific<-tagList(
    chunk_field_row(chunk_field(4, textInput(paste0(p,"analysis_variable"),"Analysis variable",chunk$analysis_variable %||% ""))),
    counting_unit_ui, rows_ui)
  else if(chunk$type%in%c("categorical_summary_nonexclusive","categorical_summary_exclusive")) specific<-tagList(
    chunk_field_row(
      chunk_field(4, selectInput(paste0(p,"den_scope"),"Denominator scope",c("header_population","chunk_source"),selected=chunk$denominator$scope)),
      chunk_field(4, selectInput(paste0(p,"den_unit"),"Denominator unit",c("distinct_subject","record","distinct_key"),selected=chunk$denominator$unit)),
      chunk_field(4, textInput(paste0(p,"den_distinct_key"),"Denominator distinct key",paste(chunk$denominator$distinct_key %||% character(),collapse=", ")))
    ),
    chunk_field_row(chunk_field(12, textAreaInput(paste0(p,"den_expression"),"Denominator expression",chunk$denominator$expression %||% "", rows=2L))),
    counting_unit_ui, rows_ui)
  else specific<-tagList(
    h4("Levels"), collection_buttons(p,"level","levels"), tagList(lapply(seq_along(chunk$levels %||% list()),function(j)level_ui(chunk$levels[[j]],p,j,chunk))),
    h4("Analysis blocks"), collection_buttons(p,"block","analysis_blocks"), tagList(lapply(seq_along(chunk$analysis_blocks %||% list()),function(b)block_ui(chunk$analysis_blocks[[b]],p,b,chunk))))
  title_bar <- tags$div(class="chunk-titlebar",
    tags$span(class="chunk-title-text", paste("Chunk", index, chunk$id)),
    tags$span(class="chunk-title-actions",
      actionButton(paste0(p,"delete"),"Delete chunk", class="btn-sm"),
      actionButton(paste0(p,"up"),"Move up", class="btn-sm"),
      actionButton(paste0(p,"down"),"Move down", class="btn-sm")
    )
  )
  box(id=paste0("chunk-card-", uid), class = "chunk-card", title=title_bar,width=12,status="info",solidHeader=TRUE,common,specific)
}

collection_buttons <- function(prefix,kind,table_name) tagList(actionButton(paste0(prefix,kind,"_new"),paste("Add",kind)),actionButton(paste0(prefix,kind,"_delete"),paste("Delete",kind)),actionButton(paste0(prefix,kind,"_up"),"Move up"),actionButton(paste0(prefix,kind,"_down"),"Move down"),DTOutput(paste0(prefix,table_name)))

statistics_controls <- function(prefix) NULL

level_ui <- function(level, prefix, index, chunk) {
  p <- paste0(prefix, "level_", index, "_")
  ids <- vapply(chunk$levels %||% list(), function(x) x$id, character(1))
  has_format <- !is.null(level$format) && nzchar(level$format)
  # A level is format-driven or variable-driven, never both: the parser rejects
  # the combination, so the note states the rule instead of describing a
  # precedence the model no longer accepts.
  format_note <- tags$small(
    class = "help-block",
    if (has_format) {
      paste0("Format supplies the node domain, the display label and the node ",
             "order. Label and order variables cannot be combined with it; ",
             "clear the format to use them instead. The format must be defined ",
             "by the calling SAS environment, and it needs NOTSORTED if its ",
             "declaration order is to be kept.")
    } else {
      paste0("Optional. A level without a format needs an order variable and ",
             "an order direction. The format must be defined by the calling ",
             "SAS environment.")
    }
  )
  tags$div(
    class = "well",
    chunk_field_row(
      chunk_field(4, readonly_editor_input(paste0(p, "id"), "Level ID", level$id)),
      chunk_field(4, selectInput(paste0(p, "parent_level"), "Parent level",
                                 c("", ids), selected = level$parent_level %||% "")),
      chunk_field(4, textInput(paste0(p, "variable"), "Variable", level$variable))
    ),
    chunk_field_row(
      chunk_field(4, textInput(paste0(p, "format"), "Format", level$format %||% "")),
      chunk_field(4, textInput(paste0(p, "label_variable"), "Label variable",
                                   level$label_variable %||% "")),
      chunk_field(4, textInput(paste0(p, "order_variable"), "Order variable",
                                 level$order_variable %||% ""))
    ),
    format_note,
    chunk_field_row(
      chunk_field(4, selectInput(paste0(p, "order_direction"), "Order direction",
                                 c("(not set)" = "", "asc" = "asc", "desc" = "desc"),
                                 selected = level$order_direction %||% "")),
      chunk_field(4, selectInput(paste0(p, "node_role"), "Node role",
                                 c("label", "analysis"), selected = level$node_role)),
      chunk_field(4, textInput(paste0(p, "node_analysis_id"), "Node analysis ID",
                                level$node_analysis_id %||% ""))
    ),
    chunk_field_row(
      chunk_field(4, selectInput(paste0(p, "missing_policy"), "Missing policy",
                                 c("exclude", "label", "error"), selected = level$missing_policy)),
      chunk_field(8, textInput(paste0(p, "missing_label"), "Missing label",
                               level$missing_label %||% ""))
    )
  )
}

block_ui <- function(block, prefix, index, chunk) {
  p <- paste0(prefix, "block_", index, "_")
  types <- c("continuous_summary", "categorical_summary_nonexclusive",
             "categorical_summary_exclusive")
  levels <- vapply(chunk$levels %||% list(), function(x) x$id, character(1))
  tags$div(
    class = "well",
    chunk_field_row(
      chunk_field(4, readonly_editor_input(paste0(p, "id"), "Block ID", block$id)),
      chunk_field(4, selectInput(paste0(p, "anchor_level"), "Anchor level",
                                 levels, selected = block$anchor_level)),
      chunk_field(4, selectInput(paste0(p, "placement"), "Placement",
                                 c("same_row", "below"), selected = block$placement))
    ),
    chunk_field_row(
      chunk_field(4, selectInput(paste0(p, "type"), "Type", types, selected = block$type)),
      chunk_field(4, selectInput(paste0(p, "counting_unit"), "Counting unit",
                                 c("record", "distinct_subject", "distinct_key"),
                                 selected = block$counting_unit)),
      chunk_field(4, textInput(paste0(p, "distinct_key"), "Distinct key",
                               paste(block$distinct_key %||% character(), collapse = ", ")))
    ),
    if (block$type == "continuous_summary") {
      chunk_field_row(
        chunk_field(4, textInput(paste0(p, "analysis_variable"), "Analysis variable",
                                 block$analysis_variable %||% ""))
      )
    } else {
      tagList(
        chunk_field_row(
          chunk_field(4, selectInput(paste0(p, "den_scope"), "Denominator scope",
                                     c("header_population", "chunk_source", "current_group"),
                                     selected = block$denominator$scope %||% "current_group")),
          chunk_field(4, selectInput(paste0(p, "den_unit"), "Denominator unit",
                                     c("record", "distinct_subject", "distinct_key"),
                                     selected = block$denominator$unit %||% "record")),
          chunk_field(4, textInput(paste0(p, "den_distinct_key"), "Denominator distinct key",
                                   paste(block$denominator$distinct_key %||% character(), collapse = ", ")))
        ),
        chunk_field_row(
          chunk_field(12, textAreaInput(paste0(p, "den_expression"), "Denominator expression",
                                        block$denominator$expression %||% "", rows = 2L))
        )
      )
    },
    h4("Rows / statistics"),
    collection_buttons(p, "row", "rows")
  )
}
