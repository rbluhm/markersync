#' Convert a PDF to Markdown via a Marker server
#'
#' Sends a PDF to a self-hosted Marker server and saves the returned
#' Markdown to `out_dir`. If the response includes embedded images, they
#' are decoded to `out_dir/figures/<stem>/` and the Markdown image links
#' are rewritten to relative paths.
#'
#' @param pdf_path Path to the input PDF file.
#' @param out_dir Output directory for the Markdown (default: `"literature/fulltext"`).
#' @param cite_key Optional citekey to use as the output filename stem.
#'   Defaults to the PDF's basename.
#' @param marker_url Full URL of the Marker upload endpoint. Read from the
#'   `MARKERSYNC_URL` environment variable if `NULL`. An error is thrown if
#'   neither is set.
#' @param marker_key API key sent as a bearer token
#'   (`Authorization: Bearer <key>`). Read from the `MY_SERVER_IVR_API_KEY`
#'   environment variable if `NULL`. This is your personal Open WebUI API
#'   key, created under *Settings -> Account -> API keys* on the Open WebUI
#'   instance that fronts the Marker server. If neither is set, the request
#'   is sent without credentials, which only works against a server that
#'   requires none.
#' @param force_ocr Pass `TRUE` to force OCR on every page (helpful for
#'   scanned PDFs).
#' @param page_range Optional zero-indexed page range, e.g. `"0,5-10,20"`.
#' @param paginate Insert page separators in the output Markdown.
#' @param timeout Request timeout in seconds (default: 1800). The server
#'   parks its models when idle and may queue a job behind in-flight LLM
#'   traffic, so a slow first byte is not a hang.
#'
#' @return Path to the written `.md` file (invisibly).
#' @export
pdf_to_md <- function(pdf_path,
                      out_dir     = "literature/fulltext",
                      cite_key    = NULL,
                      marker_url  = NULL,
                      marker_key  = NULL,
                      force_ocr   = FALSE,
                      page_range  = NULL,
                      paginate    = FALSE,
                      timeout     = 1800) {

  stopifnot(file.exists(pdf_path))

  if (is.null(marker_url)) {
    marker_url <- Sys.getenv("MARKERSYNC_URL", unset = "")
    if (!nzchar(marker_url)) {
      stop(
        "No Marker server URL configured. Either pass `marker_url` or set ",
        "the MARKERSYNC_URL environment variable, e.g. in ~/.Renviron:\n",
        "  MARKERSYNC_URL=https://your-marker-server.example.com/marker/upload"
      )
    }
  }

  body_parts <- list(
    file            = curl::form_file(pdf_path),
    force_ocr       = tolower(as.character(force_ocr)),
    paginate_output = tolower(as.character(paginate))
  )
  if (!is.null(page_range)) body_parts$page_range <- page_range

  if (is.null(marker_key)) {
    marker_key <- Sys.getenv("MY_SERVER_IVR_API_KEY", unset = "")
  }

  req <- httr2::request(marker_url)
  if (nzchar(marker_key)) {
    req <- httr2::req_auth_bearer_token(req, marker_key)
  }

  resp <- req |>
    httr2::req_body_multipart(!!!body_parts) |>
    httr2::req_timeout(timeout) |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()

  status <- httr2::resp_status(resp)
  if (status == 401) {
    if (nzchar(marker_key)) {
      stop(
        "Marker API returned 401 Unauthorized: the API key was rejected. ",
        "Check MY_SERVER_IVR_API_KEY in ~/.Renviron (it must be your ",
        "personal Open WebUI API key, and may have been revoked), and note ",
        "that ~/.Renviron overrides variables inherited from the shell.",
        call. = FALSE
      )
    }
    stop(
      "Marker API returned 401 Unauthorized and no API key was sent. Set ",
      "MY_SERVER_IVR_API_KEY in ~/.Renviron to your personal Open WebUI API ",
      "key and restart R.",
      call. = FALSE
    )
  }
  if (status == 503) {
    stop(
      "Marker API returned 503: the server could not validate API keys ",
      "(its Open WebUI backend is unreachable). This is a server-side ",
      "condition; retry in a few minutes.",
      call. = FALSE
    )
  }
  if (status == 404) {
    stop(
      "Marker API returned 404 Not Found for ", marker_url,
      ". MARKERSYNC_URL must be the full upload endpoint, ending in ",
      "/marker/upload.",
      call. = FALSE
    )
  }
  if (status != 200) {
    stop(
      "Marker API returned ", status, ":\n",
      substr(httr2::resp_body_string(resp), 1, 500),
      call. = FALSE
    )
  }

  body <- httr2::resp_body_json(resp)
  if (!isTRUE(body$success)) {
    reason <- if (!is.null(body$error)) body$error else "no reason given"
    hint <- if (grepl("out of memory", reason, ignore.case = TRUE)) {
      paste0(
        "\nThis is a server-side condition: the Marker GPU is busy with ",
        "another job. Retry in a few minutes; nothing is wrong locally."
      )
    } else ""
    stop(
      "Marker conversion failed for ", pdf_path, ":\n  ", reason, hint,
      call. = FALSE
    )
  }

  stem <- if (!is.null(cite_key)) cite_key else
    tools::file_path_sans_ext(basename(pdf_path))

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  md_file <- file.path(out_dir, paste0(stem, ".md"))
  md_text <- body$output

  if (length(body$images) > 0) {
    fig_dir <- file.path(out_dir, "figures", stem)
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

    for (img_name in names(body$images)) {
      img_bytes <- base64enc::base64decode(body$images[[img_name]])
      writeBin(img_bytes, file.path(fig_dir, img_name))

      md_text <- gsub(
        pattern     = paste0("](", img_name, ")"),
        replacement = paste0("](figures/", stem, "/", img_name, ")"),
        x           = md_text,
        fixed       = TRUE
      )
    }
    message("  ", length(body$images), " image(s) -> ", fig_dir)
  }

  writeLines(md_text, md_file)
  message("\u2713 ", stem)
  invisible(md_file)
}
