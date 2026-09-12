register_metadata_editor_template <- function(ctx) {
  input <- ctx$input
  output <- ctx$output
  template_value <- ctx$template_value
  row_table_cache <- ctx$row_table_cache
  editor_type <- ctx$editor_type
  move_item <- ctx$move_item
  mutate_template <- ctx$mutate_template
  rows_table_data <- ctx$rows_table_data
  new_chunk_seed <- ctx$new_chunk_seed

  observeEvent(input$chunk_add, {
    showModal(modalDialog(
      title = "Add chunk",
      selectInput(
        "new_chunk_type", "Chunk type",
        choices = c(
          "Continuous summary" = "continuous_summary",
          "Categorical summary (non-exclusive)" = "categorical_summary_nonexclusive",
          "Categorical summary (exclusive)" = "categorical_summary_exclusive",
          "Hierarchical summary" = "hierarchical_summary"
        )
      ),
      footer = tagList(
        actionButton("cancel_new_chunk", "Cancel"),
        actionButton("confirm_new_chunk", "Add", class = "btn-primary")
      ),
      easyClose = FALSE
    ))
  })
  observeEvent(input$cancel_new_chunk, removeModal())
  observeEvent(input$confirm_new_chunk, {
    type <- as.character(input$new_chunk_type %||% "")
    if (!type %in% c("continuous_summary", "categorical_summary_nonexclusive",
                     "categorical_summary_exclusive", "hierarchical_summary")) return()
    removeModal()
    mutate_template(function(x) {
      n <- length(x$body$chunks %||% list()) + 1L
      x$body$chunks[[n]] <- new_chunk_seed(type)
      x
    })
  })
  output$chunk_cards <- renderUI({ value<-template_value(); if(is.null(value)||editor_type()!="template")return(NULL); chunks<-value$body$chunks %||% list(); tagList(lapply(seq_along(chunks),function(i) chunk_card_ui(chunks[[i]],i))) })

  observe({
    value <- template_value(); if (is.null(value)) return()
    for (i in seq_along(value$body$chunks %||% list())) {
      chunk <- value$body$chunks[[i]]; p <- paste0("chunk_", i, "_")
      if (identical(chunk$type, "hierarchical_summary")) {
        local({ chunk_index <- i; prefix_i <- p
          output[[paste0(prefix_i,"levels")]] <- DT::renderDT({
            current <- template_value(); chunks_now <- if (is.null(current) || is.null(current$body)) list() else current$body$chunks %||% list(); current_chunk <- if (chunk_index <= length(chunks_now)) chunks_now[[chunk_index]] else list()
            data.frame(id=vapply(current_chunk$levels %||% list(),function(x)x$id,character(1)),stringsAsFactors=FALSE)
          },rownames=FALSE,selection="single",options=list(dom="t",ordering=FALSE))
          output[[paste0(prefix_i,"analysis_blocks")]] <- DT::renderDT({
            current <- template_value(); chunks_now <- if (is.null(current) || is.null(current$body)) list() else current$body$chunks %||% list(); current_chunk <- if (chunk_index <= length(chunks_now)) chunks_now[[chunk_index]] else list()
            data.frame(id=vapply(current_chunk$analysis_blocks %||% list(),function(x)x$id,character(1)),stringsAsFactors=FALSE)
          },rownames=FALSE,selection="single",options=list(dom="t",ordering=FALSE))
        })
      } else {
        local({ chunk_index <- i; prefix_i <- p
          output[[paste0(prefix_i,"rows")]] <- DT::renderDT({
            current <- template_value(); chunks_now <- if (is.null(current) || is.null(current$body)) list() else current$body$chunks %||% list(); current_chunk <- if (chunk_index <= length(chunks_now)) chunks_now[[chunk_index]] else list()
            rows_table_data(current_chunk$rows)
          },editable=list(target="cell",disable=list(columns=c(0,7))),rownames=FALSE,selection="single",
          colnames=c("Type","Label","Indent","Condition","Statistics","Digits","Cell format",".row_id"),
          options=list(dom="t",ordering=FALSE,columnDefs=list(list(visible=FALSE,targets=7))))
        })
      }
      if (identical(chunk$type, "hierarchical_summary")) for (b in seq_along(chunk$analysis_blocks %||% list())) {
        local({ chunk_index <- i; block_index <- b; bp <- paste0(p, "block_", b, "_")
          output[[paste0(bp, "rows")]] <- DT::renderDT({
            current <- template_value(); chunks_now <- if (is.null(current) || is.null(current$body)) list() else current$body$chunks %||% list(); current_chunk <- if (chunk_index <= length(chunks_now)) chunks_now[[chunk_index]] else list(); blocks_now <- current_chunk$analysis_blocks %||% list(); current_block <- if (block_index <= length(blocks_now)) blocks_now[[block_index]] else list()
            rows_table_data(current_block$rows)
          }, editable=list(target="cell",disable=list(columns=c(0,7))), rownames=FALSE, selection="single",
            colnames=c("Type","Label","Indent","Condition","Statistics","Digits","Cell format",".row_id"), options=list(dom="t",ordering=FALSE,columnDefs=list(list(visible=FALSE,targets=7))))
        })
      }
    }
  })

  observer_registry <- new.env(parent = emptyenv())
  reset_template_action_observers <- function() {
    keys <- ls(observer_registry, all.names = TRUE)
    for (key in keys) {
      observer <- get(key, observer_registry, inherits = FALSE)
      if (!is.null(observer) && is.function(observer$destroy)) observer$destroy()
      rm(list = key, envir = observer_registry)
    }
  }
  register_once <- function(key, factory) {
    if (exists(key, observer_registry, inherits = FALSE)) return(invisible(NULL))
    assign(key, factory(), observer_registry)
    invisible(NULL)
  }
  register_template_actions <- observe({
    value<-template_value(); if(is.null(value))return(); chunks<-value$body$chunks %||% list()
    lapply(seq_along(chunks),function(i){ local({index<-i
        register_dt_edit <- function(prefix, rows_getter) {
        register_once(paste0("dt-", prefix, "-rows-edit"), function() observeEvent(input[[paste0(prefix, "rows_cell_edit")]], {
          info <- input[[paste0(prefix, "rows_cell_edit")]]; cache <- row_table_cache()
          key <- paste0(prefix, "rows"); data <- cache[[key]] %||% rows_table_data(rows_getter())
          row <- as.integer(info$row); col <- as.integer(info$col) + 1L
          if (row >= 1L && row <= nrow(data) && col >= 2L && col <= 7L) {
            data[row, col] <- if (col == 3L) suppressWarnings(as.integer(info$value)) else as.character(info$value)
            cache[[key]] <- data; row_table_cache(cache)
          }
        }, ignoreInit=TRUE))
      }
      register_dt_edit(paste0("chunk_", index, "_"), function() (template_value()$body$chunks[[index]]$rows %||% list()))
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b; register_dt_edit(paste0("chunk_", index, "_block_", block_index, "_"), function() (template_value()$body$chunks[[index]]$analysis_blocks[[block_index]]$rows %||% list())) })
      register_statistic_actions <- function(prefix, block_index = NULL) {
        for (action in c("new", "delete", "up", "down")) local({ a <- action
          register_once(paste0("stat-", prefix, "-", a), function() observeEvent(input[[paste0(prefix, "statistic_", a)]], {
            mutate_template(function(x) {
              rows <- if (is.null(block_index)) x$body$chunks[[index]]$rows %||% list() else x$body$chunks[[index]]$analysis_blocks[[block_index]]$rows %||% list()
              row_selected <- input[[paste0(prefix, "rows_rows_selected")]]
              stat_selected <- input[[paste0(prefix, "statistics_rows_selected")]]
              if (a == "new") {
                row_pos <- if (length(row_selected)) row_selected[[1L]] else if (length(rows)) 1L else NA_integer_
                if (!is.na(row_pos)) {
                  analysis_type <- if (is.null(block_index)) x$body$chunks[[index]]$type else x$body$chunks[[index]]$analysis_blocks[[block_index]]$type
                  allowed <- if (identical(analysis_type,"continuous_summary")) c("n","mean","sd","median","q1","q3","min","max") else c("n","pct")
                  existing <- vapply(rows[[row_pos]]$statistics %||% list(),function(s)s$id,character(1)); next_id <- setdiff(allowed,existing)
                  if (length(next_id)) rows[[row_pos]]$statistics[[length(existing)+1L]] <- list(id=next_id[[1L]])
                }
              } else {
                map <- do.call(rbind, lapply(seq_along(rows), function(r) if(length(rows[[r]]$statistics %||% list())) cbind(row=r,stat=seq_along(rows[[r]]$statistics))))
                flat <- if (length(stat_selected)) stat_selected[[1L]] else if (!is.null(map)) nrow(map) else NA_integer_
                if (!is.null(map) && flat >= 1L && flat <= nrow(map)) {
                  row_pos <- map[flat,"row"]; stat_pos <- map[flat,"stat"]; stats <- rows[[row_pos]]$statistics
                  if (a == "delete") stats <- stats[-stat_pos] else stats <- move_item(stats, stat_pos, a)
                  rows[[row_pos]]$statistics <- stats
                }
              }
              if (is.null(block_index)) x$body$chunks[[index]]$rows <- rows else x$body$chunks[[index]]$analysis_blocks[[block_index]]$rows <- rows
              x
            })
          }, ignoreInit=TRUE))
        })
      }
      register_statistic_actions(paste0("chunk_", index, "_"))
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b; register_statistic_actions(paste0("chunk_", index, "_block_", block_index, "_"), block_index) })
      register_once(paste0("chunk-",index,"-delete"),function() observeEvent(input[[paste0("chunk_",index,"_delete")]],mutate_template(function(x){x$body$chunks<-x$body$chunks[-index];x}),ignoreInit=TRUE))
      register_once(paste0("chunk-",index,"-up"),function() observeEvent(input[[paste0("chunk_",index,"_up")]], {
        current <- template_value(); chunks_now <- current$body$chunks %||% list()
        if (index > 1L && index <= length(chunks_now)) mutate_template(function(x){x$body$chunks<-move_item(x$body$chunks,index,"up");x})
      }, ignoreInit=TRUE))
      register_once(paste0("chunk-",index,"-down"),function() observeEvent(input[[paste0("chunk_",index,"_down")]], {
        current <- template_value(); chunks_now <- current$body$chunks %||% list()
        if (index >= 1L && index < length(chunks_now)) mutate_template(function(x){x$body$chunks<-move_item(x$body$chunks,index,"down");x})
      }, ignoreInit=TRUE))
      for(kind in c("row","level","block")) for(action in c("new","delete","up","down")) local({k<-kind;a<-action
        register_once(paste0("chunk-",index,"-",k,"-",a),function() observeEvent(input[[paste0("chunk_",index,"_",k,"_",a)]],{
          mutate_template(function(x){ch<-x$body$chunks[[index]]; field<-switch(k,row="rows",level="levels",block="analysis_blocks");items<-ch[[field]] %||% list(); selected<-input[[paste0("chunk_",index,"_",field,"_rows_selected")]]; pos<-if(length(selected))selected[[1L]] else length(items)
            if(a=="new") { n<-length(items)+1L; items[[n]]<-switch(k,row=list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}"),level=list(id="level",variable="VAR",order_variable="VAR",order_direction="asc",node_role="label",missing_policy="exclude"),block=list(id="analysis",anchor_level=(ch$levels[[1L]]$id %||% "level"),placement="below",type="continuous_summary",counting_unit="record",analysis_variable="AVAL",rows=list(list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}")))) }
            if(a=="delete"&&length(selected))items<-items[-pos]; if(a%in%c("up","down")&&length(selected))items<-move_item(items,pos,a); ch[[field]]<-items;x$body$chunks[[index]]<-ch;x })
        },ignoreInit=TRUE))
      })
      for (b in seq_along(chunks[[index]]$analysis_blocks %||% list())) local({ block_index <- b
        for (action in c("new", "delete", "up", "down")) local({ a <- action
          register_once(paste0("chunk-", index, "-block-", block_index, "-row-", a), function() observeEvent(input[[paste0("chunk_", index, "_block_", block_index, "_row_", a)]], {
            mutate_template(function(x) {
              block <- x$body$chunks[[index]]$analysis_blocks[[block_index]]; items <- block$rows %||% list()
              selected <- input[[paste0("chunk_", index, "_block_", block_index, "_rows_rows_selected")]]; pos <- if(length(selected)) selected[[1L]] else length(items)
              if (a == "new") items[[length(items)+1L]] <- list(id="row",type="analysis",label="New row",statistics=list(list(id="n")),cell_format="{n}")
              if (a == "delete" && length(selected)) items <- items[-pos]
              if (a %in% c("up","down") && length(selected)) items <- move_item(items,pos,a)
              block$rows <- items; x$body$chunks[[index]]$analysis_blocks[[block_index]] <- block; x
            })
          }, ignoreInit=TRUE))
        })
      })
    })})
  })

}
