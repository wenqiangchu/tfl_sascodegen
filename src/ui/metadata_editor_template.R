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
  if(chunk$type=="continuous_summary") specific<-tagList(
    chunk_field_row(chunk_field(4, textInput(paste0(p,"analysis_variable"),"Analysis variable",chunk$analysis_variable %||% ""))), rows_ui)
  else if(chunk$type%in%c("categorical_summary_nonexclusive","categorical_summary_exclusive")) specific<-tagList(
    chunk_field_row(
      chunk_field(4, selectInput(paste0(p,"den_type"),"Denominator type",c("header_population","non_missing","custom"),selected=chunk$denominator$type)),
      chunk_field(4, textInput(paste0(p,"den_variable"),"Denominator variable",chunk$denominator$variable %||% "")),
      chunk_field(4, textInput(paste0(p,"den_expression"),"Denominator expression",chunk$denominator$expression %||% ""))
    ), rows_ui)
  else { sc<-chunk$source_contract %||% list(); specific<-tagList(
    h4("Source contract"), chunk_field_row(
      chunk_field(4, selectInput(paste0(p,"grain"),"Grain",c("subject","record","observation"),selected=sc$grain)),
      chunk_field(4, textInput(paste0(p,"subject_key"),"Subject key",sc$subject_key %||% "")),
      chunk_field(4, selectInput(paste0(p,"duplicate_policy"),"Duplicate policy",c("error","first","last"),selected=sc$duplicate_policy))
    ), chunk_field_row(chunk_field(8, textInput(paste0(p,"record_key"),"Record key",paste(sc$record_key %||% character(),collapse=", ")))),
    h4("Levels"), collection_buttons(p,"level","levels"), tagList(lapply(seq_along(chunk$levels %||% list()),function(j)level_ui(chunk$levels[[j]],p,j,chunk))),
    h4("Analysis blocks"), collection_buttons(p,"block","analysis_blocks"), tagList(lapply(seq_along(chunk$analysis_blocks %||% list()),function(b)block_ui(chunk$analysis_blocks[[b]],p,b,chunk)))) }
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

level_ui <- function(level,prefix,index,chunk) { p<-paste0(prefix,"level_",index,"_"); ids<-vapply(chunk$levels %||% list(),function(x)x$id,character(1)); tags$div(class="well",chunk_field_row(chunk_field(4,readonly_editor_input(paste0(p,"id"),"Level ID",level$id)),chunk_field(4,selectInput(paste0(p,"parent_level"),"Parent level",c("",ids),selected=level$parent_level %||% "")),chunk_field(4,textInput(paste0(p,"variable"),"Variable",level$variable))),chunk_field_row(chunk_field(4,textInput(paste0(p,"label_variable"),"Label variable",level$label_variable %||% "")),chunk_field(4,textInput(paste0(p,"order_variable"),"Order variable",level$order_variable)),chunk_field(4,selectInput(paste0(p,"order_direction"),"Order direction",c("asc","desc"),selected=level$order_direction))),chunk_field_row(chunk_field(4,selectInput(paste0(p,"node_role"),"Node role",c("label","analysis"),selected=level$node_role)),chunk_field(4,textInput(paste0(p,"node_analysis_id"),"Node analysis ID",level$node_analysis_id %||% "")),chunk_field(4,selectInput(paste0(p,"missing_policy"),"Missing policy",c("exclude","label","error"),selected=level$missing_policy))),chunk_field_row(chunk_field(8,textInput(paste0(p,"missing_label"),"Missing label",level$missing_label %||% ""))) ) }

block_ui <- function(block,prefix,index,chunk) { p<-paste0(prefix,"block_",index,"_"); types<-c("continuous_summary","categorical_summary_nonexclusive","categorical_summary_exclusive"); levels<-vapply(chunk$levels %||% list(),function(x)x$id,character(1)); tags$div(class="well",chunk_field_row(chunk_field(4,readonly_editor_input(paste0(p,"id"),"Block ID",block$id)),chunk_field(4,selectInput(paste0(p,"anchor_level"),"Anchor level",levels,selected=block$anchor_level)),chunk_field(4,selectInput(paste0(p,"placement"),"Placement",c("same_row","below"),selected=block$placement))),chunk_field_row(chunk_field(4,selectInput(paste0(p,"type"),"Type",types,selected=block$type)),chunk_field(4,selectInput(paste0(p,"counting_unit"),"Counting unit",c("record","distinct_subject","distinct_key"),selected=block$counting_unit)),chunk_field(4,textInput(paste0(p,"distinct_key"),"Distinct key",paste(block$distinct_key %||% character(),collapse=", ")))),if(block$type=="continuous_summary") chunk_field_row(chunk_field(4,textInput(paste0(p,"analysis_variable"),"Analysis variable",block$analysis_variable %||% "")) ) else tagList(chunk_field_row(chunk_field(4,selectInput(paste0(p,"den_scope"),"Denominator scope",c("header_population","current_group","non_missing","custom"),selected=block$denominator$scope)),chunk_field(4,selectInput(paste0(p,"den_unit"),"Denominator unit",c("record","distinct_subject","distinct_key"),selected=block$denominator$unit)),chunk_field(4,textInput(paste0(p,"den_variable"),"Denominator variable",block$denominator$variable %||% ""))),chunk_field_row(chunk_field(8,textInput(paste0(p,"den_expression"),"Denominator expression",block$denominator$expression %||% "")))),h4("Rows / statistics"),collection_buttons(p,"row","rows")) }
