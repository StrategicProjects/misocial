# Serve pages by cursorMark, as the MI Social Solr does: `pages` is a list of
# document lists and `totals` the numFound reported on each page.
cursor_server <- function(pages, totals = sum(lengths(pages)), on_call = NULL) {
  totals <- rep_len(totals, length(pages))
  function(query, ...) {
    i <- if (identical(query$cursorMark, "*")) 1L
    else as.integer(query$cursorMark)
    if (!is.null(on_call)) on_call(query)
    list(response = list(numFound = totals[[i]], docs = pages[[i]]),
         nextCursorMark = as.character(min(i + 1L, length(pages))))
  }
}
