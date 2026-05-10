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
#' @param force_ocr Pass `TRUE` to force OCR on every page (helpful for
#'   scanned PDFs).
#' @param page_range Optional zero-indexed page range, e.g. `"0,5-10,20"`.
#' @param paginate Insert page separators in the output Markdown.
#' @param timeout Request timeout in seconds (default: 600).
#'
#' @return Path to the written `.md` file (invisibly).
#' @export
pdf_to_md <- function(pdf_path,
                      out_dir     = "literature/fulltext",
                      cite_key    = NULL,
                      marker_url  = NULL,
                      marker_user = NULL,
                      marker_pass = NULL,
                      force_ocr   = FALSE,
                      page_range  = NULL,
                      paginate    = FALSE,
                      timeout     = 600) {

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

  req <- httr2::request(marker_url)

  if (!is.null(marker_user) && !is.null(marker_pass)) {
    req <- req |>
      httr2::req_auth_basic(username = marker_user, password = marker_pass)
  } else {
    marker_user <- Sys.getenv("MARKERSYNC_USER", unset = "")
    marker_pass <- Sys.getenv("MARKERSYNC_PASS", unset = "")
    if (nzchar(marker_user) && nzchar(marker_pass)) {
      req <- req |>
        httr2::req_auth_basic(username = marker_user, password = marker_pass)
    }
  }

  resp <- req |>
    httr2::req_body_multipart(!!!body_parts) |>
    httr2::req_timeout(timeout) |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200) {
    stop(
      "Marker API returned ", httr2::resp_status(resp), ":\n",
      substr(httr2::resp_body_string(resp), 1, 500)
    )
  }

  body <- httr2::resp_body_json(resp)
  if (!isTRUE(body$success)) stop("Marker conversion failed for ", pdf_path)

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
