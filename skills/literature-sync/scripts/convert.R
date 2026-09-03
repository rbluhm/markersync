#!/usr/bin/env Rscript
# Ad-hoc Marker conversion: one file in, Markdown out.
#
# Independent of the Zotero/Obsidian note workflow and of the markersync
# package itself -- it needs only httr2, curl and base64enc, so it works on a
# machine where only the server credentials are configured.
#
# Usage:
#   Rscript convert.R <path|ZOTEROKEY> [options]
#
# Options:
#   --out <dir>     directory for the .md (default: ~/.cache/markersync,
#                   so nothing is written into the user's project)
#   --name <stem>   output basename (default: the input filename)
#   --pages <range> convert a page range only, e.g. 0-9 (0-based)
#   --ocr           force OCR (scanned documents)
#   --timeout <s>   server timeout in seconds (default 1800; the server may
#                   queue a job behind LLM traffic before it starts)
#   --print         write the whole Markdown to stdout
#   --head <n>      preview the first n lines (default 40; ignored with --print)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage: Rscript convert.R <path|ZOTEROKEY> [--out DIR] [--name STEM]",
      "[--pages 0-9] [--ocr] [--timeout 600] [--print | --head N]\n")
  quit(status = 2)
}

flag <- function(f) f %in% args
opt  <- function(f, default = NULL) {
  i <- match(f, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}

target  <- args[[1]]
# NB: not tempfile() -- R deletes its session tempdir on exit, which would
# take the converted Markdown with it the moment this script returns.
cache_root <- file.path(Sys.getenv("XDG_CACHE_HOME", unset = path.expand("~/.cache")),
                        "markersync")
out_dir <- opt("--out", cache_root)
stem    <- opt("--name")
pages   <- opt("--pages")
timeout <- as.numeric(opt("--timeout", "1800"))
head_n  <- as.integer(opt("--head", "40"))

for (p in c("httr2", "curl", "base64enc")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("required package '", p, "' is not installed", call. = FALSE)
}

# --- Resolve the input -----------------------------------------------------
# A bare 8-character Zotero item key is looked up in ZOTERO_STORAGE; anything
# else is treated as a path.
if (grepl("^[A-Z0-9]{8}$", target)) {
  storage <- Sys.getenv("ZOTERO_STORAGE", unset = path.expand("~/Zotero/storage"))
  dir <- file.path(storage, target)
  if (!dir.exists(dir))
    stop("no Zotero attachment folder for key ", target, " under ", storage, call. = FALSE)
  hits <- list.files(dir, "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (length(hits) == 0)
    stop("Zotero folder ", dir, " contains no PDF (linked file, or not synced yet)",
         call. = FALSE)
  path <- hits[[1]]
} else {
  path <- path.expand(target)
}
if (!file.exists(path)) stop("file not found: ", path, call. = FALSE)
if (is.null(stem)) stem <- tools::file_path_sans_ext(basename(path))

marker_url <- Sys.getenv("MARKERSYNC_URL", unset = "")
if (!nzchar(marker_url))
  stop("MARKERSYNC_URL is not set -- see references/setup.md", call. = FALSE)
# Personal Open WebUI API key, sent as a bearer token. Absent means the
# request goes out unauthenticated, which only a server without auth accepts.
api_key <- Sys.getenv("MY_SERVER_IVR_API_KEY", unset = "")

cat("Converting: ", path, " (", format(file.size(path), big.mark = ","), " bytes)\n", sep = "")

# --- Send ------------------------------------------------------------------
body <- list(file = curl::form_file(path),
             force_ocr = tolower(as.character(flag("--ocr"))),
             paginate_output = "false")
if (!is.null(pages)) body$page_range <- pages

req <- httr2::request(marker_url)
if (nzchar(api_key)) req <- httr2::req_auth_bearer_token(req, api_key)
req <- httr2::req_body_multipart(req, !!!body)
req <- httr2::req_error(httr2::req_timeout(req, timeout), is_error = function(r) FALSE)

resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
if (inherits(resp, "error"))
  stop("could not reach the Marker server: ", conditionMessage(resp), call. = FALSE)

status <- httr2::resp_status(resp)
if (status == 401) {
  if (nzchar(api_key))
    stop("401 Unauthorized -- the API key was rejected. Check MY_SERVER_IVR_API_KEY ",
         "(your personal Open WebUI key; it may have been revoked)", call. = FALSE)
  stop("401 Unauthorized -- no API key sent. Set MY_SERVER_IVR_API_KEY in ~/.Renviron",
       call. = FALSE)
}
if (status == 503)
  stop("503 -- the server cannot validate API keys right now (its Open WebUI backend ",
       "is unreachable). Server-side; retry in a few minutes.", call. = FALSE)
if (status == 404) stop("404 Not Found -- MARKERSYNC_URL should end in /marker/upload", call. = FALSE)
if (status != 200)
  stop("Marker returned HTTP ", status, ":\n",
       substr(httr2::resp_body_string(resp), 1, 500), call. = FALSE)

out <- httr2::resp_body_json(resp)
# The API answers 200 even on failure; the real reason is in $error.
if (!isTRUE(out$success)) {
  msg <- if (!is.null(out$error)) out$error else "no reason given"
  if (grepl("out of memory", msg, ignore.case = TRUE)) {
    stop("the Marker server's GPU is out of memory -- another job is holding it.\n",
         "This is a server-side condition; retry in a few minutes.\n  ", msg, call. = FALSE)
  }
  stop("Marker could not convert this file:\n  ", msg, call. = FALSE)
}

# --- Write -----------------------------------------------------------------
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
md <- out$output
n_img <- length(out$images)
if (n_img > 0) {
  fig_dir <- file.path(out_dir, "figures", stem)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  for (nm in names(out$images)) {
    writeBin(base64enc::base64decode(out$images[[nm]]), file.path(fig_dir, nm))
    md <- gsub(paste0("](", nm, ")"), paste0("](figures/", stem, "/", nm, ")"), md, fixed = TRUE)
  }
}
md_file <- file.path(out_dir, paste0(stem, ".md"))
writeLines(md, md_file)

# --- Report ----------------------------------------------------------------
lines <- strsplit(md, "\n", fixed = TRUE)[[1]]
words <- length(strsplit(md, "\\s+")[[1]])
cat("\n--- converted ---\n")
cat("output:  ", md_file, "\n", sep = "")
if (n_img > 0) cat("images:  ", n_img, " -> ", file.path(out_dir, "figures", stem), "\n", sep = "")
cat("size:    ", format(nchar(md), big.mark = ","), " chars / ",
    format(words, big.mark = ","), " words / ~",
    format(round(nchar(md) / 4), big.mark = ","), " tokens\n", sep = "")

if (flag("--print")) {
  cat("\n--- markdown ---\n"); cat(md, "\n")
} else {
  cat("\n--- first ", min(head_n, length(lines)), " of ", length(lines), " lines ---\n", sep = "")
  cat(paste(utils::head(lines, head_n), collapse = "\n"), "\n")
  if (length(lines) > head_n)
    cat("\n[... ", length(lines) - head_n, " more lines. Read ", md_file,
        " for the rest, or re-run with --print ...]\n", sep = "")
}
