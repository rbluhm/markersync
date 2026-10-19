test_that("the request timeout controls slow Marker responses", {
  pdf <- tempfile(fileext = ".pdf")
  writeLines("%PDF-1.4 stub", pdf)
  request_options <- NULL
  mock <- function(req) {
    request_options <<- req$options
    httr2::response(
      status_code = 200,
      body = charToRaw('{"success": true, "output": "# hi", "images": {}}'),
      headers = list("Content-Type" = "application/json")
    )
  }

  suppressMessages(httr2::with_mocked_responses(mock, {
    pdf_to_md(
      pdf,
      out_dir = tempfile(),
      marker_url = "https://example.test/marker/upload",
      timeout = 3600
    )
  }))

  expect_equal(request_options$timeout_ms, 3600000)
  expect_equal(request_options$low_speed_time, 0)
})
