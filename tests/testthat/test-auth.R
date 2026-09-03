# pdf_to_md() authentication, exercised against mocked HTTP so no server or
# key is needed. Each mock records the Authorization header it received.

pdf_fixture <- function() {
  f <- tempfile(fileext = ".pdf")
  writeLines("%PDF-1.4 stub", f)
  f
}

ok_body <- function() {
  charToRaw('{"success": true, "format": "markdown", "output": "# hi", "images": {}}')
}

with_marker_mock <- function(status, body, code) {
  # req_get_headers(redacted = "reveal") is needed to read the (redacted)
  # Authorization header back out of the request; it arrived in httr2 1.1.0.
  testthat::skip_if_not_installed("httr2", "1.1.0")
  seen <- NULL
  mock <- function(req) {
    seen <<- httr2::req_get_headers(req, redacted = "reveal")$Authorization
    httr2::response(status_code = status, body = body,
                    headers = list("Content-Type" = "application/json"))
  }
  suppressMessages(httr2::with_mocked_responses(mock, code))
  seen
}

test_that("an explicit marker_key is sent as a bearer token", {
  out <- tempfile()
  seen <- with_marker_mock(200, ok_body(), {
    pdf_to_md(pdf_fixture(), out_dir = out, cite_key = "x",
              marker_url = "https://example.test/marker/upload",
              marker_key = "sk-explicit")
  })
  expect_equal(as.character(seen), "Bearer sk-explicit")
  expect_true(file.exists(file.path(out, "x.md")))
})

test_that("MY_SERVER_IVR_API_KEY is used when marker_key is NULL", {
  withr::local_envvar(MY_SERVER_IVR_API_KEY = "sk-from-env")
  seen <- with_marker_mock(200, ok_body(), {
    pdf_to_md(pdf_fixture(), out_dir = tempfile(), cite_key = "x",
              marker_url = "https://example.test/marker/upload")
  })
  expect_equal(as.character(seen), "Bearer sk-from-env")
})

test_that("no key at all sends no Authorization header", {
  withr::local_envvar(MY_SERVER_IVR_API_KEY = NA)
  seen <- with_marker_mock(200, ok_body(), {
    pdf_to_md(pdf_fixture(), out_dir = tempfile(), cite_key = "x",
              marker_url = "https://example.test/marker/upload")
  })
  expect_null(seen)
})

test_that("basic-auth variables are ignored", {
  withr::local_envvar(MY_SERVER_IVR_API_KEY = NA,
                      MARKERSYNC_USER = "u", MARKERSYNC_PASS = "p")
  seen <- with_marker_mock(200, ok_body(), {
    pdf_to_md(pdf_fixture(), out_dir = tempfile(), cite_key = "x",
              marker_url = "https://example.test/marker/upload")
  })
  expect_null(seen)
})

test_that("401 with a key says the key was rejected", {
  expect_error(
    with_marker_mock(401, charToRaw("invalid key"), {
      pdf_to_md(pdf_fixture(), out_dir = tempfile(),
                marker_url = "https://example.test/marker/upload",
                marker_key = "sk-bad")
    }),
    "API key was rejected"
  )
})

test_that("401 without a key says no key was sent", {
  withr::local_envvar(MY_SERVER_IVR_API_KEY = NA)
  expect_error(
    with_marker_mock(401, raw(0), {
      pdf_to_md(pdf_fixture(), out_dir = tempfile(),
                marker_url = "https://example.test/marker/upload")
    }),
    "no API key was sent"
  )
})

test_that("503 is reported as a server-side key-validation outage", {
  expect_error(
    with_marker_mock(503, raw(0), {
      pdf_to_md(pdf_fixture(), out_dir = tempfile(),
                marker_url = "https://example.test/marker/upload",
                marker_key = "sk-any")
    }),
    "could not validate API keys"
  )
})

test_that("a 200 with success=false surfaces the server's reason", {
  body <- charToRaw('{"success": false, "error": "CUDA out of memory"}')
  expect_error(
    with_marker_mock(200, body, {
      pdf_to_md(pdf_fixture(), out_dir = tempfile(),
                marker_url = "https://example.test/marker/upload",
                marker_key = "sk-any")
    }),
    "server-side"
  )
})
