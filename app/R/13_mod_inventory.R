# Page 4 - Inventory: the user's own product catalogue and a stockout simulator --------------
# This page works with USER-PROVIDED store data (or clearly labelled sample records), kept
# in the visitor's browser. It never changes the FreshRetailNet-50K research data. A
# catalogue item can be linked to a research product; the link only adds the research
# signals (stockout chance, suggestion, weekday pattern) - research values are normalised,
# so they are never converted into the user's item counts.

INV_STATUS_KIND <- c("Out of stock" = "critical", "Expired" = "critical", "At or below reorder level" = "warning",
                     "Expires soon" = "warning", "OK" = "good")
INV_SOURCE_LABEL <- c(sample = "Sample record", user = "Your data", import = "Imported")

mod_inventory_ui <- function(id) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    htmltools::div(class = "rp-hero",
      htmltools::div(htmltools::div(class = "rp-eyebrow", "Your store"),
        htmltools::h1("Inventory & stock simulator"),
        htmltools::p("Keep a list of your own products and test how long the stock may last if demand or a delivery changes."))),
    htmltools::div(class = "rp-info-banner", shiny::icon("circle-info"), htmltools::div(
      htmltools::strong("Your own store data, saved only in this browser. "),
      "It is kept separate from the FreshRetailNet-50K research data used on the other pages, whose product IDs are anonymous and whose sales are in normalised units. ",
      "Use Export CSV to keep a copy or move it to another device.", shiny::uiOutput(ns("storage_note"), inline = TRUE))),
    shiny::uiOutput(ns("kpis")),
    bslib::card(
      bslib::card_header(rp_card_title("Product catalogue", "search, sort, filter · edit or delete any row", "boxes-stacked")),
      htmltools::div(class = "rp-inv-toolbar",
        htmltools::div(class = "rp-inv-filters",
          shiny::selectInput(ns("f_status"), NULL, width = "230px", choices = c("All stock statuses" = "", stats::setNames(names(INV_STATUS_KIND), names(INV_STATUS_KIND)),
                                                                 "Expired or expiring within 3 days" = "expiry")),
          shiny::selectInput(ns("f_cat"), NULL, width = "180px", choices = c("All categories" = "")),
          shiny::actionLink(ns("f_reset"), "Reset filters", class = "rp-link")),
        htmltools::div(class = "rp-inv-buttons",
          shiny::actionButton(ns("add"), "Add product", icon = shiny::icon("plus"), class = "btn-primary btn-sm"),
          shiny::actionButton(ns("import"), "Import CSV", icon = shiny::icon("file-import"), class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("export"), "Export CSV", class = "btn-outline-secondary btn-sm"),
          shiny::downloadButton(ns("template"), "CSV template", class = "btn-outline-secondary btn-sm"),
          shiny::actionButton(ns("sample"), "Add sample records", icon = shiny::icon("flask"), class = "btn-outline-secondary btn-sm"),
          shiny::actionButton(ns("clear"), "Clear all", icon = shiny::icon("trash"), class = "btn-outline-danger btn-sm"))),
      shiny::uiOutput(ns("table_wrap"))),
    bslib::card(id = ns("sim_card"),
      bslib::card_header(rp_card_title("Stockout simulator", "hypothetical: what if demand or a delivery changes?", "sliders")),
      shiny::uiOutput(ns("sim_empty")),
      htmltools::div(id = ns("sim_body"),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, lg = c(4, 8)),
          htmltools::div(class = "rp-sim-inputs",
            shiny::selectInput(ns("sim_sku"), "Product", choices = NULL, width = "100%"),
            htmltools::div(class = "rp-sim-row",
              shiny::numericInput(ns("sim_stock"), "Stock on hand (items)", value = "", min = 0, step = 1, width = "100%"),
              shiny::numericInput(ns("sim_demand"), "Expected sales per day (items)", value = "", min = 0, step = 0.5, width = "100%")),
            shiny::uiOutput(ns("sim_pattern_ui")),
            shiny::sliderInput(ns("sim_mult"), "Scenario: demand change", min = -50, max = 100, value = 0, step = 5, post = "%", width = "100%"),
            htmltools::div(class = "rp-sim-row",
              shiny::numericInput(ns("sim_lead"), "Supplier lead time (days)", value = "", min = 0, max = 365, step = 1, width = "100%"),
              shiny::numericInput(ns("sim_delay"), "Scenario: extra delivery delay (days)", value = 0, min = 0, max = 60, step = 1, width = "100%")),
            htmltools::div(class = "rp-sim-row",
              shiny::numericInput(ns("sim_safety"), "Safety stock (items)", value = "", min = 0, step = 1, width = "100%"),
              shiny::radioButtons(ns("sim_h"), "Look ahead", choices = c("7 days" = "7", "14 days" = "14", "30 days" = "30"), selected = "14", inline = TRUE)),
            htmltools::div(class = "rp-dl-row",
              shiny::actionButton(ns("sim_reset"), "Reset to product values", icon = shiny::icon("rotate-left"), class = "btn-outline-secondary btn-sm"),
              shiny::downloadButton(ns("sim_dl"), "Export simulation (CSV)", class = "btn-outline-secondary btn-sm"))),
          htmltools::div(
            shiny::uiOutput(ns("sim_compare")),
            plotly::plotlyOutput(ns("sim_plot"), height = "300px"),
            shiny::uiOutput(ns("sim_note")),
            shiny::uiOutput(ns("sim_research"))))))
  )
}

mod_inventory_server <- function(id, RP, state, catalogue, save_catalogue, storage_ok, recs_r, goto_product) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pid_choices <- c("Not linked" = "", RP$product_choices)
    editing <- shiny::reactiveVal(NULL)          # NULL = adding, otherwise the SKU being edited
    pending_delete <- shiny::reactiveVal(NULL)
    import_v <- shiny::reactiveVal(NULL)

    cat_df <- shiny::reactive({ x <- catalogue(); if (is.null(x)) inv_empty() else x })
    with_status <- shiny::reactive({ x <- cat_df(); x$status <- inv_status(x); x })
    notify <- function(msg, type = "message") shiny::showNotification(msg, type = type, duration = 4)

    output$storage_note <- shiny::renderUI({
      if (isFALSE(storage_ok())) htmltools::span(class = "rp-warn-inline", " Saving is blocked in this browser (for example, private mode): changes last until you close the page, so export a CSV.")
    })

    # ---- KPI cards (click to filter) ----
    output$kpis <- shiny::renderUI({
      x <- with_status()
      card <- function(title, value, sub, icon, tone, filter) htmltools::tagAppendAttributes(
        rp_kpi(title, value, sub, icon, tone), class = "rp-kpi-click", role = "button", tabindex = "0",
        `data-rp-input` = ns("kpi_filter"), `data-rp-value` = filter, title = "Click to filter the catalogue")
      n_out <- sum(x$status %in% c("Out of stock")); n_low <- sum(x$status == "At or below reorder level")
      n_exp <- sum(inv_expiring(x)); n_link <- sum(!is.na(x$linked_product_id))
      htmltools::div(class = "rp-kpis rp-kpis-4",
        card("Products in catalogue", nrow(x), if (any(x$source == "sample")) sprintf("%d are sample records", sum(x$source == "sample")) else "your own records", "boxes-stacked", "neutral", ""),
        card("Out of stock", n_out, "stock on hand is 0", "store-slash", if (n_out) "critical" else "good", "Out of stock"),
        card("At or below reorder level", n_low, "stock ≤ your reorder level", "triangle-exclamation", if (n_low) "warning" else "good", "At or below reorder level"),
        card("Expiring soon or expired", n_exp, "within 3 days, from your expiry dates", "calendar-xmark", if (n_exp) "warning" else "good", "expiry"))
    })
    shiny::observeEvent(input$kpi_filter, {
      v <- input$kpi_filter$value
      shiny::updateSelectInput(session, "f_status", selected = v)
    })
    shiny::observeEvent(input$f_reset, { shiny::updateSelectInput(session, "f_status", selected = ""); shiny::updateSelectInput(session, "f_cat", selected = "") })
    shiny::observe({
      cats <- sort(unique(stats::na.omit(cat_df()$category[nzchar(cat_df()$category)])))
      shiny::updateSelectInput(session, "f_cat", choices = c("All categories" = "", stats::setNames(cats, cats)), selected = shiny::isolate(input$f_cat) %||% "")
    })

    # ---- catalogue table ----
    filtered <- shiny::reactive({
      x <- with_status()
      f <- input$f_status %||% ""
      if (f == "expiry") x <- x[inv_expiring(x), ] else if (nzchar(f)) x <- x[x$status == f, ]
      if (nzchar(input$f_cat %||% "")) x <- x[x$category == input$f_cat, ]
      x
    })
    output$table_wrap <- shiny::renderUI({
      if (!nrow(cat_df())) return(htmltools::div(class = "rp-empty-state", shiny::icon("boxes-stacked"),
        htmltools::h4("Your catalogue is empty"),
        htmltools::p("Add your products one by one, import a CSV (download the template first), or add a few sample records to try the page."),
        htmltools::div(class = "rp-dl-row rp-center",
          htmltools::tags$button(class = "btn btn-primary btn-sm", `data-rp-input` = ns("empty_action"), `data-rp-value` = "add", shiny::icon("plus"), " Add product"),
          htmltools::tags$button(class = "btn btn-outline-secondary btn-sm", `data-rp-input` = ns("empty_action"), `data-rp-value` = "import", shiny::icon("file-import"), " Import CSV"),
          htmltools::tags$button(class = "btn btn-outline-secondary btn-sm", `data-rp-input` = ns("empty_action"), `data-rp-value` = "sample", shiny::icon("flask"), " Add sample records"))))
      reactable::reactableOutput(ns("table"))
    })
    shiny::observeEvent(input$empty_action, switch(input$empty_action$value, add = open_form(NULL), import = open_import(), sample = add_sample()))

    output$table <- reactable::renderReactable({
      x <- filtered()
      if (!nrow(x)) return(reactable::reactable(data.frame(Message = "No products match these filters. Use “Reset filters” to see everything.")))
      recs <- recs_r(); top <- recs[!duplicated(recs$product_id), ]
      risk <- RP$risk_next$risk[match(x$linked_product_id, RP$risk_next$product_id)]
      act <- top$action[match(x$linked_product_id, top$product_id)]
      tb <- data.frame(sku = x$sku, Product = x$name, Category = x$category, Price = x$price, Stock = x$stock, Reorder = x$reorder_level,
                       Lead = x$lead_time_days, Expiry = x$expiry_date, Status = x$status, Source = unname(INV_SOURCE_LABEL[x$source]),
                       Research = ifelse(is.na(x$linked_product_id), "", sprintf("%s|%s|%s|%s", x$linked_product_id, plabel(x$linked_product_id), fmt_pct(risk), ifelse(is.na(act), "", act))),
                       Actions = x$sku, check.names = FALSE, stringsAsFactors = FALSE)
      btn <- function(act, sku, icon, label, cls = "") htmltools::tags$button(type = "button", class = paste("rp-icon-btn", cls), title = label, `aria-label` = paste(label, sku),
                                                                         `data-rp-input` = ns("row"), `data-rp-value` = paste0(act, "\t", sku), shiny::icon(icon))
      reactable::reactable(tb, searchable = TRUE, highlight = TRUE, compact = TRUE, defaultPageSize = 10, defaultSorted = "Product",
        language = reactable::reactableLang(searchPlaceholder = "Search name, SKU or category…"),
        columns = list(
          sku = reactable::colDef(name = "SKU", width = 120, style = list(fontWeight = 600, color = RP_COL$forest)),
          Product = reactable::colDef(minWidth = 170),
          Category = reactable::colDef(width = 110),
          Price = reactable::colDef(width = 80, align = "right", format = reactable::colFormat(digits = 2)),
          Stock = reactable::colDef(width = 72, align = "right"),
          Reorder = reactable::colDef(name = "Reorder at", width = 88, align = "right"),
          Lead = reactable::colDef(name = "Lead (d)", width = 76, align = "right"),
          Expiry = reactable::colDef(width = 100),
          Status = reactable::colDef(width = 170, cell = function(v) rp_badge(v, INV_STATUS_KIND[[v]])),
          Source = reactable::colDef(width = 110, cell = function(v) rp_badge(v, if (v == "Sample record") "gold" else "neutral")),
          Research = reactable::colDef(name = "Research link", minWidth = 160, sortable = FALSE, cell = function(v) {
            if (!nzchar(v)) return(htmltools::span(class = "rp-sub", "not linked"))
            p <- strsplit(v, "|", fixed = TRUE)[[1]]
            htmltools::tags$button(type = "button", class = "rp-linkish", `data-rp-input` = ns("open_research"), `data-rp-value` = p[1],
                                   title = "Open this research product's analysis", sprintf("%s · %s stockout chance", p[2], p[3]))
          }),
          Actions = reactable::colDef(name = "", width = 110, sortable = FALSE, cell = function(v) htmltools::div(class = "rp-row-actions",
            btn("sim", v, "sliders", "Simulate"), btn("edit", v, "pen", "Edit"), btn("del", v, "trash", "Delete", "danger")))))
    })
    shiny::observeEvent(input$open_research, goto_product(as.integer(input$open_research$value)))
    shiny::observeEvent(input$row, {
      p <- strsplit(input$row$value, "\t", fixed = TRUE)[[1]]; act <- p[1]; sku <- p[2]
      if (!sku %in% cat_df()$sku) return(notify("That product no longer exists.", "warning"))
      if (act == "edit") open_form(sku)
      else if (act == "del") confirm_delete(sku)
      else if (act == "sim") { shiny::updateSelectInput(session, "sim_sku", selected = sku); fill_sim(sku); session$sendCustomMessage("rp-scroll", list(id = ns("sim_card"))) }
    })

    # ---- add / edit form ----
    open_form <- function(sku) {
      editing(sku)
      r <- if (is.null(sku)) NULL else cat_df()[cat_df()$sku == sku, ][1, ]
      val <- function(k, d = NA) if (is.null(r) || is.na(r[[k]])) d else r[[k]]
      cats <- sort(unique(c(cat_df()$category[nzchar(cat_df()$category)], "Bakery", "Dairy", "Drinks", "Fruit & veg", "Frozen", "Meat & fish", "Pantry")))
      shiny::showModal(shiny::modalDialog(title = if (is.null(sku)) "Add a product" else sprintf("Edit %s", sku), size = "l", easyClose = FALSE,
        htmltools::p(class = "rp-sub", "Fields marked * are required. Values are your own store data, not research data."),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, md = c(6, 6)),
          shiny::textInput(ns("f_sku"), "SKU / product code *", value = val("sku", ""), placeholder = "e.g. MILK-1L"),
          shiny::textInput(ns("f_name"), "Product name *", value = val("name", ""), placeholder = "e.g. Whole milk 1 L"),
          shiny::selectizeInput(ns("f_category"), "Category", choices = c("", cats), selected = val("category", ""), options = list(create = TRUE, placeholder = "Choose or type a new one")),
          shiny::numericInput(ns("f_price"), "Selling price (optional)", value = val("price"), min = 0, step = 0.01),
          shiny::numericInput(ns("f_stock"), "Stock on hand (items) *", value = val("stock"), min = 0, step = 1),
          shiny::numericInput(ns("f_reorder"), "Reorder level (items)", value = val("reorder_level", 0), min = 0, step = 1),
          shiny::numericInput(ns("f_lead"), "Supplier lead time (days)", value = val("lead_time_days"), min = 0, max = 365, step = 1),
          shiny::textInput(ns("f_expiry"), "Expiry date (optional, YYYY-MM-DD)", value = val("expiry_date", ""), placeholder = format(Sys.Date() + 7, "%Y-%m-%d"))),
        shiny::selectizeInput(ns("f_link"), "Link to a research product (optional)", choices = pid_choices, selected = if (is.null(r) || is.na(r$linked_product_id)) "" else r$linked_product_id, width = "100%"),
        htmltools::p(class = "rp-sub", "Only link if you know this is the same kind of product. The link shows that product's historical stockout chance and weekday pattern; it never converts research numbers into your item counts."),
        shiny::uiOutput(ns("form_errors")),
        footer = htmltools::tagList(shiny::modalButton("Cancel"), shiny::actionButton(ns("save"), "Save product", icon = shiny::icon("check"), class = "btn-primary"))))
    }
    output$form_errors <- shiny::renderUI(NULL)
    shiny::observeEvent(input$add, open_form(NULL))
    shiny::observeEvent(input$save, {
      chr <- function(x) if (is.null(x) || (length(x) == 1 && is.na(x))) "" else as.character(x)
      row <- data.frame(sku = chr(input$f_sku), name = chr(input$f_name), category = chr(input$f_category), price = chr(input$f_price),
                        stock = chr(input$f_stock), reorder_level = chr(input$f_reorder), lead_time_days = chr(input$f_lead),
                        expiry_date = chr(input$f_expiry), linked_product_id = chr(input$f_link), stringsAsFactors = FALSE)
      x <- cat_df(); others <- x$sku[is.null(editing()) | x$sku != (editing() %||% "")]
      v <- inv_validate(row, existing_skus = others, valid_pids = RP$products$product_id)
      e <- c(v$errors[[1]], if (isTRUE(v$duplicate_existing[1])) sprintf("SKU %s is already in your catalogue", trimws(row$sku)))
      if (length(e)) { output$form_errors <- shiny::renderUI(htmltools::div(class = "rp-form-errors", htmltools::strong("Please fix: "), htmltools::tags$ul(lapply(e, htmltools::tags$li)))); return() }
      new <- v$rows; new$updated <- format(Sys.time(), "%Y-%m-%d %H:%M")
      if (is.null(editing())) { new$source <- "user"; x <- rbind(x, new[, names(x)]); msg <- sprintf("Added %s.", new$name) }
      else { i <- which(x$sku == editing()); new$source <- if (x$source[i] == "sample") "user" else x$source[i]; x[i, names(x)] <- new[, names(x)]; msg <- sprintf("Saved changes to %s.", new$name) }
      save_catalogue(x); output$form_errors <- shiny::renderUI(NULL); shiny::removeModal(); notify(msg)
    })

    # ---- delete / clear ----
    confirm_delete <- function(sku) {
      pending_delete(sku); r <- cat_df()[cat_df()$sku == sku, ][1, ]
      shiny::showModal(shiny::modalDialog(title = "Delete this product?", easyClose = TRUE,
        htmltools::p(sprintf("%s (%s) will be removed from your catalogue in this browser. This cannot be undone, unless you have an exported CSV.", r$name, r$sku)),
        footer = htmltools::tagList(shiny::modalButton("Keep it"), shiny::actionButton(ns("del_ok"), "Delete", icon = shiny::icon("trash"), class = "btn-danger"))))
    }
    shiny::observeEvent(input$del_ok, {
      sku <- pending_delete(); x <- cat_df(); nm <- x$name[x$sku == sku]
      save_catalogue(x[x$sku != sku, , drop = FALSE]); shiny::removeModal(); notify(sprintf("Deleted %s.", nm)); pending_delete(NULL)
    })
    shiny::observeEvent(input$clear, {
      if (!nrow(cat_df())) return(notify("The catalogue is already empty."))
      shiny::showModal(shiny::modalDialog(title = "Clear the whole catalogue?", easyClose = TRUE,
        htmltools::p(sprintf("All %d products will be removed from this browser. Export a CSV first if you want to keep them.", nrow(cat_df()))),
        footer = htmltools::tagList(shiny::modalButton("Cancel"), shiny::actionButton(ns("clear_ok"), "Clear all", class = "btn-danger"))))
    })
    shiny::observeEvent(input$clear_ok, { save_catalogue(inv_empty()); shiny::removeModal(); notify("Catalogue cleared.") })

    # ---- sample records ----
    add_sample <- function() {
      x <- cat_df(); s <- inv_sample()
      new <- s[!s$sku %in% x$sku, ]
      if (!nrow(new)) return(notify("The sample records are already in your catalogue."))
      save_catalogue(rbind(x, new[, names(x)])); notify(sprintf("Added %d sample records. They are made up for demonstration, not real store data.", nrow(new)))
    }
    shiny::observeEvent(input$sample, add_sample())

    # ---- CSV template / export ----
    output$template <- shiny::downloadHandler(filename = "retailpulse_catalogue_template.csv",
      content = function(file) utils::write.csv(inv_template(), file, row.names = FALSE, na = ""))
    output$export <- shiny::downloadHandler(filename = function() sprintf("retailpulse_catalogue_%s.csv", format(Sys.Date(), "%Y%m%d")),
      content = function(file) {
        x <- with_status()
        out <- x[, INV_COLS]; out$linked_product_id <- ifelse(is.na(out$linked_product_id), "", plabel(out$linked_product_id))
        out$status <- x$status; out$source <- unname(INV_SOURCE_LABEL[x$source]); out$last_updated <- x$updated
        utils::write.csv(out, file, row.names = FALSE, na = "")
      })

    # ---- CSV import with preview ----
    open_import <- function() {
      import_v(NULL)
      shiny::showModal(shiny::modalDialog(title = "Import products from a CSV file", size = "xl", easyClose = FALSE,
        htmltools::p("Required columns: sku, name, stock. Optional: category, price, reorder_level, lead_time_days, expiry_date (YYYY-MM-DD), linked_product_id (e.g. P108). ",
                     "Nothing is added until you confirm below."),
        bslib::layout_columns(col_widths = bslib::breakpoints(sm = 12, md = c(6, 6)),
          shiny::fileInput(ns("csv"), "Choose a CSV file", accept = c(".csv", "text/csv"), width = "100%"),
          shiny::radioButtons(ns("dup"), "If a SKU is already in your catalogue", choices = c("Keep my existing record (skip the row)" = "skip", "Replace it with the row from the file" = "update"), selected = "skip")),
        shiny::uiOutput(ns("import_preview")),
        footer = htmltools::tagList(shiny::modalButton("Cancel"),
          shiny::downloadButton(ns("import_rejects"), "Download rows with problems", class = "btn-outline-secondary"),
          shiny::actionButton(ns("import_ok"), "Import valid rows", icon = shiny::icon("check"), class = "btn-primary"))))
    }
    shiny::observeEvent(input$import, open_import())
    shiny::observeEvent(input$csv, {
      f <- input$csv; shiny::req(f)
      df <- tryCatch(utils::read.csv(f$datapath, colClasses = "character", check.names = FALSE, strip.white = TRUE, na.strings = character(), encoding = "UTF-8", fileEncoding = "UTF-8-BOM"),
                     error = function(e) NULL)
      v <- if (is.null(df)) list(ok = FALSE, file_error = "This file could not be read as a CSV. Save it from Excel or Sheets as “CSV (comma separated)” and try again.")
           else inv_validate(df, existing_skus = cat_df()$sku, valid_pids = RP$products$product_id)
      v$file_name <- f$name; import_v(v)
    })
    output$import_preview <- shiny::renderUI({
      v <- import_v(); if (is.null(v)) return(htmltools::p(class = "rp-sub", "No file chosen yet."))
      if (!isTRUE(v$ok)) return(htmltools::div(class = "rp-form-errors", htmltools::strong(v$file_name %||% "File", ": "), v$file_error))
      ok <- lengths(v$errors) == 0; dup <- v$duplicate_existing
      tb <- data.frame(Row = seq_along(ok) + 1L, SKU = v$rows$sku, Name = v$rows$name, Stock = v$rows$stock,
                       Result = ifelse(!ok, "Will be rejected", ifelse(dup, if (identical(input$dup, "update")) "Will replace existing" else "Skipped: SKU exists", "Will be added")),
                       Problems = vapply(v$errors, paste, "", collapse = "; "), stringsAsFactors = FALSE)
      kind <- c("Will be rejected" = "critical", "Will replace existing" = "warning", "Skipped: SKU exists" = "neutral", "Will be added" = "good")
      htmltools::tagList(
        htmltools::div(class = "rp-import-summary",
          rp_badge(sprintf("%d rows read", length(ok)), "neutral"), rp_badge(sprintf("%d valid", sum(ok)), "good"),
          rp_badge(sprintf("%d with problems", sum(!ok)), if (any(!ok)) "critical" else "neutral"), rp_badge(sprintf("%d SKUs already exist", sum(ok & dup)), if (any(ok & dup)) "warning" else "neutral"),
          if (length(v$ignored_columns)) rp_badge(sprintf("ignored columns: %s", paste(v$ignored_columns, collapse = ", ")), "neutral")),
        if (any(!ok)) htmltools::p(class = "rp-sub", "Rows with problems are not imported. Download them, fix the values in the Problems column, and import that file again."),
        reactable::reactable(tb, compact = TRUE, searchable = TRUE, defaultPageSize = 8, columns = list(
          Row = reactable::colDef(width = 60), Stock = reactable::colDef(width = 70),
          Result = reactable::colDef(width = 170, cell = function(x) rp_badge(x, kind[[x]])),
          Problems = reactable::colDef(minWidth = 260, style = list(color = RP_COL$red, fontSize = "0.82rem")))))
    })
    output$import_rejects <- shiny::downloadHandler(filename = "retailpulse_rows_to_fix.csv", content = function(file) {
      v <- import_v()
      if (is.null(v) || !isTRUE(v$ok)) { utils::write.csv(data.frame(message = "No rows to fix"), file, row.names = FALSE); return() }
      bad <- lengths(v$errors) > 0
      out <- v$rows[bad, , drop = FALSE]; out$problems <- vapply(v$errors[bad], paste, "", collapse = "; ")
      utils::write.csv(out, file, row.names = FALSE, na = "")
    })
    shiny::observeEvent(input$import_ok, {
      v <- import_v()
      if (is.null(v)) return(notify("Choose a CSV file first.", "warning"))
      if (!isTRUE(v$ok)) return(notify("This file cannot be imported; see the message in the window.", "error"))
      if (!any(lengths(v$errors) == 0)) return(notify("No valid rows to import. Fix the problems and try again.", "warning"))
      r <- inv_merge(cat_df(), v, input$dup %||% "skip", source = "import")
      save_catalogue(r$catalogue); shiny::removeModal(); import_v(NULL)
      notify(sprintf("Imported: %d added, %d replaced, %d skipped (SKU already existed), %d rejected.", r$added, r$updated, r$skipped_duplicates, r$rejected))
    })

    # ---- simulator ----
    shiny::observe({
      x <- cat_df()
      ch <- if (nrow(x)) stats::setNames(x$sku, sprintf("%s · %s", x$name, x$sku)) else character()
      sel <- shiny::isolate(state$sim_sku %||% input$sim_sku); if (is.null(sel) || !sel %in% x$sku) sel <- shiny::isolate(input$sim_sku)
      if (is.null(sel) || !sel %in% x$sku) sel <- if (length(ch)) ch[[1]] else NULL
      shiny::updateSelectInput(session, "sim_sku", choices = ch, selected = sel)
    })
    output$sim_empty <- shiny::renderUI({
      if (!nrow(cat_df())) htmltools::div(class = "rp-empty-state rp-empty-small", htmltools::p("Add at least one product to the catalogue to run a simulation."))
    })
    shiny::observe(shinyjs_toggle(session, ns("sim_body"), nrow(cat_df()) > 0))
    rec_of <- function(sku) { x <- cat_df(); x[x$sku == sku, , drop = FALSE] }
    fill_sim <- function(sku) {
      r <- rec_of(sku); if (!nrow(r)) return()
      shiny::updateNumericInput(session, "sim_stock", value = r$stock)
      shiny::updateNumericInput(session, "sim_lead", value = if (is.na(r$lead_time_days)) 0 else r$lead_time_days)
      shiny::updateNumericInput(session, "sim_safety", value = r$reorder_level)
      shiny::updateSliderInput(session, "sim_mult", value = 0); shiny::updateNumericInput(session, "sim_delay", value = 0)
    }
    shiny::observeEvent(input$sim_sku, if (nzchar(input$sim_sku %||% "")) fill_sim(input$sim_sku), ignoreInit = FALSE)
    shiny::observeEvent(input$sim_reset, { fill_sim(input$sim_sku %||% ""); notify("Simulator reset to this product's catalogue values.") })
    shiny::observeEvent(state$sim_sku, {                 # opened from another page
      s <- state$sim_sku; if (is.null(s) || !s %in% cat_df()$sku) return()
      shiny::updateSelectInput(session, "sim_sku", selected = s); fill_sim(s)
      session$sendCustomMessage("rp-scroll", list(id = ns("sim_card")))
    }, ignoreNULL = TRUE)

    sim_rec <- shiny::reactive({ shiny::req(input$sim_sku); r <- rec_of(input$sim_sku); shiny::req(nrow(r) == 1); r })
    linked_pattern <- shiny::reactive({
      pid <- sim_rec()$linked_product_id; if (is.na(pid)) return(NULL)
      f <- RP$forecast_next[RP$forecast_next$product_id == pid & RP$forecast_next$.model == RP$manifest$chosen_model, ]
      f <- utils::head(f[order(f$dt), ], 7); if (nrow(f) < 7 || mean(f$mean) <= 0) return(NULL)
      list(pid = pid, w = f$mean / mean(f$mean), days = format(f$dt, "%a"))
    })
    output$sim_pattern_ui <- shiny::renderUI({
      p <- linked_pattern()
      if (is.null(p)) return(htmltools::p(class = "rp-sub", "Demand is spread evenly over the days. Link this product to a research product to use a weekday pattern."))
      shiny::checkboxInput(ns("sim_pattern"), sprintf("Follow %s's weekday pattern from its forecast (busiest %s, %s of average)",
                                                      plabel(p$pid), p$days[which.max(p$w)], fmt_pct(max(p$w), 0)), value = FALSE)
    })
    sim <- shiny::reactive({
      num <- function(x) if (is.null(x) || length(x) != 1 || is.na(x)) NA_real_ else as.numeric(x)
      st <- num(input$sim_stock); dm <- num(input$sim_demand); ld <- num(input$sim_lead); dl <- num(input$sim_delay); sf <- num(input$sim_safety)
      shiny::validate(
        shiny::need(!is.na(st), "Enter the stock on hand."), shiny::need(is.na(st) || st >= 0, "Stock on hand cannot be negative."),
        shiny::need(!is.na(dm), "Enter the expected sales per day (your own estimate, in items)."), shiny::need(is.na(dm) || dm >= 0, "Expected sales per day cannot be negative."),
        shiny::need(is.na(ld) || (ld >= 0 && ld <= 365), "Lead time must be between 0 and 365 days."),
        shiny::need(is.na(dl) || (dl >= 0 && dl <= 60), "Delivery delay must be between 0 and 60 days."),
        shiny::need(is.na(sf) || sf >= 0, "Safety stock cannot be negative."))
      h <- as.integer(input$sim_h %||% "14"); pat <- if (isTRUE(input$sim_pattern) && !is.null(linked_pattern())) linked_pattern()$w else NULL
      ld <- if (is.na(ld)) 0 else ld; dl <- if (is.na(dl)) 0 else dl; sf <- if (is.na(sf)) 0 else sf
      mult <- 1 + (input$sim_mult %||% 0) / 100
      base <- inv_simulate(st, inv_demand_path(dm, h, 1, pat), lead = ld, delay = 0, safety = sf)
      scen <- inv_simulate(st, inv_demand_path(dm, h, mult, pat), lead = ld, delay = dl, safety = sf)
      list(base = base, scen = scen, h = h, mult = mult, delay = dl, lead = ld, safety = sf, demand = dm, stock = st, pattern = !is.null(pat))
    })
    output$sim_compare <- shiny::renderUI({
      s <- sim(); b <- s$base; c <- s$scen
      dtxt <- function(x) if (is.infinite(x$days_left)) sprintf("more than %d days", x$horizon) else if (x$days_left == 0) "already out" else sprintf("%s days", fmt_num(x$days_left, 1))
      sday <- function(x) if (is.na(x$below_safety_day)) "not within the period" else if (x$below_safety_day == 0) "already below" else sprintf("day %d", x$below_safety_day)
      arr <- function(x) if (is.na(x$stock_at_arrival)) sprintf("after day %d (outside the period)", ceiling(x$arrival_day)) else sprintf("%s items left on day %s", fmt_num(x$stock_at_arrival, 0), fmt_num(x$arrival_day, 0))
      tile <- function(lbl, a, z, expl) htmltools::div(htmltools::div(class = "rp-lbl", lbl),
        htmltools::div(class = "vals", htmltools::span(class = "base", a), htmltools::span(class = "arrow", "→"), htmltools::span(class = paste("scen", if (!identical(a, z)) "changed"), z)),
        htmltools::p(class = "expl", expl))
      htmltools::tagList(
        htmltools::div(class = "rp-sim-legend", rp_badge("Your assumptions", "neutral"), htmltools::span("→"), rp_badge("Hypothetical scenario", "gold"),
                       htmltools::span(class = "rp-sub", sprintf("demand %s%s, delivery delay +%s days", if (s$mult >= 1) "+" else "−", fmt_pct(abs(s$mult - 1), 0), fmt_num(s$delay, 0)))),
        htmltools::div(class = "rp-compare",
          tile("Stock lasts", dtxt(b), dtxt(c), "At the expected daily sales, with no new delivery."),
          tile("Falls below safety stock", sday(b), sday(c), sprintf("Safety stock: %s items.", fmt_num(s$safety, 0))),
          tile("If ordered today, delivery arrives", arr(b), arr(c), sprintf("Lead time %s days%s.", fmt_num(s$lead, 0), if (s$delay > 0) sprintf(" + %s days delay in the scenario", fmt_num(s$delay, 0)) else "")),
          tile("Sales at risk before delivery", sprintf("%s items", fmt_num(b$unmet_before_arrival, 0)), sprintf("%s items", fmt_num(c$unmet_before_arrival, 0)), "Demand that could not be served from current stock before the delivery.")))
    })
    output$sim_plot <- plotly::renderPlotly({
      s <- sim(); b <- s$base$path; c <- s$scen$path
      p <- plotly::plot_ly() |>
        plotly::add_lines(data = b, x = ~day, y = ~stock, name = "Your assumptions", line = list(color = RP_COL$forest2, width = 2.4, shape = "linear")) |>
        plotly::add_lines(data = c, x = ~day, y = ~stock, name = "Hypothetical scenario", line = list(color = RP_COL$gold, width = 2.4, dash = "dash"))
      shapes <- list(list(type = "line", x0 = 0, x1 = s$h, y0 = s$safety, y1 = s$safety, line = list(color = RP_COL$red, dash = "dot", width = 1.2)))
      for (a in unique(c(s$base$arrival_day, s$scen$arrival_day))) if (a > 0 && a <= s$h)
        shapes[[length(shapes) + 1]] <- list(type = "line", x0 = a, x1 = a, yref = "paper", y0 = 0, y1 = 1, line = list(color = RP_COL$muted, dash = "dot", width = 1))
      rp_plotly_layout(p, ytitle = "Items in stock (projected)", xtitle = "Days from today") |>
        plotly::layout(shapes = shapes, xaxis = list(range = c(0, s$h), dtick = if (s$h > 14) 5 else 1),
                       annotations = list(list(x = s$h, y = s$safety, xanchor = "right", yanchor = "bottom", text = "safety stock", showarrow = FALSE, font = list(size = 10, color = RP_COL$red))))
    })
    output$sim_note <- shiny::renderUI({
      s <- sim(); c <- s$scen; b <- s$base
      verdict <- if (s$stock <= 0) "This product is already out of stock."
        else if (s$demand == 0) "With zero expected sales, the stock does not run down."
        else if (c$runs_out_before_arrival) sprintf("In the scenario, stock may run out after about %s days, before a delivery ordered today would arrive (day %s). Stock may be insufficient for this period.", fmt_num(c$days_left, 1), fmt_num(c$arrival_day, 0))
        else if (is.finite(c$days_left)) sprintf("In the scenario, stock lasts about %s days; a delivery ordered today would arrive first (day %s).", fmt_num(c$days_left, 1), fmt_num(c$arrival_day, 0))
        else sprintf("In the scenario, stock lasts beyond the %d-day period.", s$h)
      rp_note(htmltools::strong(verdict), " ",
        sprintf("Hypothetical simulation from the numbers you entered%s. It is not live stock data, does not schedule a delivery and does not recommend an order quantity.",
                if (s$pattern) sprintf(", with daily sales shaped by %s's weekday pattern (research forecast, normalised units used only as relative weights)", plabel(linked_pattern()$pid)) else ""))
    })
    output$sim_research <- shiny::renderUI({
      r <- sim_rec(); pid <- r$linked_product_id; if (is.na(pid)) return(NULL)
      risk <- RP$risk_next$risk[RP$risk_next$product_id == pid]
      rec <- recs_r(); rec <- rec[rec$product_id == pid, ]
      htmltools::div(class = "rp-research-box",
        htmltools::div(htmltools::strong(sprintf("Research signal for linked product %s", plabel(pid))), rp_badge("Historical research data", "info")),
        htmltools::p(sprintf("Chance of a stockout tomorrow from past sell-out patterns: %s. Suggested action: %s%s.", fmt_pct(risk),
                             if (nrow(rec)) rec$action[1] else "none", if (nrow(rec)) sprintf(" (%s urgency) — %s", rec$urgency[1], rec$reason[1]) else "")),
        htmltools::tags$button(type = "button", class = "btn btn-outline-secondary btn-sm", `data-rp-input` = ns("open_research"), `data-rp-value` = pid,
                               shiny::icon("magnifying-glass-chart"), sprintf(" Open %s analysis", plabel(pid))))
    })
    output$sim_dl <- shiny::downloadHandler(filename = function() sprintf("retailpulse_simulation_%s.csv", gsub("[^A-Za-z0-9_-]", "_", input$sim_sku %||% "product")),
      content = function(file) {
        s <- sim(); b <- s$base$path; c <- s$scen$path
        out <- data.frame(sku = input$sim_sku, day = b$day, expected_demand_assumptions = round(b$demand, 3), stock_assumptions = round(b$stock, 3),
                          expected_demand_scenario = round(c$demand, 3), stock_scenario = round(c$stock, 3),
                          note = "Hypothetical simulation from user-entered values; not live inventory data")
        utils::write.csv(out, file, row.names = FALSE)
      })
  })
}

# show/hide an element by id without extra packages
shinyjs_toggle <- function(session, id, show) session$sendCustomMessage("rp-toggle", list(id = id, show = isTRUE(show)))
