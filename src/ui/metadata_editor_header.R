register_metadata_editor_header <- function(ctx) {
  input <- ctx$input; output <- ctx$output; header_table <- ctx$header_table
  output$header_columns_table <- DT::renderDT(
    header_table() %||% data.frame(),
    editable = list(target = "cell", disable = list(columns = 0)),
    rownames = FALSE, selection = "single", options = list(ordering = FALSE)
  )
  observeEvent(input$header_columns_table_cell_edit, {
    info <- input$header_columns_table_cell_edit; data <- header_table()
    if (is.null(data)) return()
    row <- as.integer(info$row); column <- as.integer(info$col) + 1L
    if (row < 1L || row > nrow(data) || column < 1L || column > ncol(data) || column == 1L) return()
    field <- names(data)[[column]]; value <- info$value
    if (field == "display_order") value <- suppressWarnings(as.integer(value))
    else if (field == "width") value <- suppressWarnings(as.numeric(value))
    else value <- as.character(value)
    data[row, field] <- value; header_table(data)
  })
  observeEvent(input$header_column_new, {
    data <- header_table(); if (is.null(data)) return(); n <- nrow(data) + 1L
    used <- as.character(data$id %||% character()); next_n <- n
    while (sprintf("column_%03d", next_n) %in% used) next_n <- next_n + 1L
    data <- rbind(data, data.frame(id = sprintf("column_%03d", next_n),
      label = "New column", condition = "1", display_order = n, width = 1,
      alignment = "center", spanning_header_1 = "", spanning_header_2 = "",
      stringsAsFactors = FALSE))
    header_table(data)
  })
  observeEvent(input$header_column_delete, {
    data <- header_table(); row <- input$header_columns_table_rows_selected
    if (is.null(data) || !length(row)) return()
    header_table(data[-row[[1L]], , drop = FALSE])
  })
}
