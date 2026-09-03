#!/usr/bin/env Rscript
# markersync environment doctor.
#
# Checks every link in the Zotero -> Obsidian -> Marker chain and prints a
# verdict per link. Never prints secret values, only whether they are set.
#
# Usage: Rscript doctor.R [notes_dir] [fulltext_dir]

args <- commandArgs(trailingOnly = TRUE)
notes_dir <- if (length(args) >= 1) args[[1]] else "literature/notes"
full_dir  <- if (length(args) >= 2) args[[2]] else "literature/fulltext"

problems <- character()
ok   <- function(...) cat("  [ok]   ", ..., "\n", sep = "")
warn <- function(...) cat("  [warn] ", ..., "\n", sep = "")
bad  <- function(...) { cat("  [FAIL] ", ..., "\n", sep = ""); problems <<- c(problems, paste0(...)) }

# --- 1. R and package ------------------------------------------------------
cat("\n1. R and markersync package\n")
ok("R ", as.character(getRversion()), " at ", R.home())

installed <- "markersync" %in% rownames(installed.packages())
if (installed) {
  ok("markersync ", as.character(packageVersion("markersync")),
     " visible on .libPaths()")
} else {
  # The classic failure: an R minor-version upgrade moves the user library
  # from .../4.5 to .../4.6 and leaves every package behind.
  lib_parent <- dirname(.libPaths()[[1]])
  stranded <- Sys.glob(file.path(lib_parent, "*", "markersync"))
  if (length(stranded) > 0) {
    bad("markersync NOT visible to R ", as.character(getRversion()),
        ", but found in an older library: ", paste(stranded, collapse = ", "),
        "\n           -> R was upgraded and left the package behind. Reinstall:",
        "\n              remotes::install_github(\"rbluhm/markersync\", upgrade = \"never\")")
  } else {
    bad("markersync is not installed.",
        "\n           -> remotes::install_github(\"rbluhm/markersync\", upgrade = \"never\")")
  }
}

for (p in c("httr2", "curl", "base64enc")) {
  if (p %in% rownames(installed.packages())) {
    ok("dependency ", p, " ", as.character(packageVersion(p)))
  } else {
    bad("dependency ", p, " missing -> install.packages(\"", p, "\")")
  }
}

# --- 2. Configuration ------------------------------------------------------
cat("\n2. Configuration (~/.Renviron)\n")
renviron <- path.expand("~/.Renviron")
if (file.exists(renviron)) ok(renviron, " exists") else
  bad("no ~/.Renviron -- nothing will be configured. See references/setup.md")

marker_url <- Sys.getenv("MARKERSYNC_URL",        unset = "")
api_key    <- Sys.getenv("MY_SERVER_IVR_API_KEY", unset = "")
zot        <- Sys.getenv("ZOTERO_STORAGE",        unset = "")

if (nzchar(marker_url)) ok("MARKERSYNC_URL = ", marker_url) else
  bad("MARKERSYNC_URL not set -> ask your Marker server admin for the /marker/upload URL")
if (nzchar(api_key)) ok("MY_SERVER_IVR_API_KEY set (value hidden)") else
  warn("MY_SERVER_IVR_API_KEY not set -- fine only if the server needs no authentication.",
       "
           Otherwise create a personal API key in Open WebUI",
       " (Settings -> Account -> API keys) and add it to ~/.Renviron")
# Basic auth was removed in markersync 0.4.0; leftover credentials are
# harmless but misleading when someone reads their .Renviron.
if (nzchar(Sys.getenv("MARKERSYNC_USER")) || nzchar(Sys.getenv("MARKERSYNC_PASS")))
  warn("MARKERSYNC_USER / MARKERSYNC_PASS are set but no longer used",
       " (basic auth was replaced by the API key) -- remove them from ~/.Renviron")

# --- 3. Zotero storage -----------------------------------------------------
cat("\n3. Zotero storage\n")
candidates <- c(
  zot,
  path.expand("~/Zotero/storage"),
  path.expand("~/snap/zotero-snap/common/Zotero/storage"),
  path.expand("~/.var/app/org.zotero.Zotero/data/Zotero/storage"),
  path.expand("~/Library/Application Support/Zotero/storage")
)
candidates <- unique(candidates[nzchar(candidates)])
found <- candidates[dir.exists(candidates)]

if (!nzchar(zot)) {
  if (length(found) > 0) {
    bad("ZOTERO_STORAGE not set, but a Zotero storage dir exists at: ", found[[1]],
        "\n           -> add ZOTERO_STORAGE=", found[[1]], " to ~/.Renviron")
  } else {
    bad("ZOTERO_STORAGE not set and no Zotero storage dir found in the usual places")
  }
} else if (!dir.exists(zot)) {
  bad("ZOTERO_STORAGE points at a directory that does not exist: ", zot,
      if (length(found) > 0) paste0("\n           -> did you mean ", found[[1]], "?") else "")
} else {
  n <- length(list.dirs(zot, recursive = FALSE))
  ok("ZOTERO_STORAGE = ", zot, " (", n, " attachment folders)")
  if (n == 0) warn("storage is empty -- is Zotero syncing attachments to this machine?")
}

# --- 4. Vault layout -------------------------------------------------------
cat("\n4. Vault layout\n")
if (dir.exists(notes_dir)) {
  notes <- list.files(notes_dir, "\\.md$")
  ok(notes_dir, " (", length(notes), " notes)")
  if (length(notes) == 0)
    warn("no notes yet -- import one from Zotero via the Obsidian Zotero Integration plugin")
} else {
  bad("notes dir not found: ", notes_dir,
      "\n           -> run this from your vault/project root, or pass the path as argument 1")
}
if (dir.exists(full_dir)) {
  ok(full_dir, " (", length(list.files(full_dir, "\\.md$")), " fulltexts)")
} else {
  warn(full_dir, " does not exist yet -- sync_fulltext() will create it")
}

# --- 5. Marker server ------------------------------------------------------
cat("\n5. Marker server\n")
if (nzchar(marker_url) && requireNamespace("httr2", quietly = TRUE)) {
  probe <- function(url) {
    req <- httr2::request(url)
    if (nzchar(api_key)) req <- httr2::req_auth_bearer_token(req, api_key)
    req <- httr2::req_error(httr2::req_timeout(req, 20), is_error = function(r) FALSE)
    tryCatch(httr2::req_perform(req), error = function(e) e)
  }
  # Preferred probe: GET <base>/health answers 200 once the key is accepted
  # and Marker is up. Servers without a health route fall back to a bare GET
  # on the upload endpoint, which is POST-only: 405 means "reachable and
  # authenticated".
  health_url <- if (grepl("/upload/?$", marker_url)) sub("/upload/?$", "/health", marker_url)
                else paste0(sub("/+$", "", marker_url), "/health")
  resp <- probe(health_url); probed <- health_url
  if (!inherits(resp, "error") && httr2::resp_status(resp) == 404) {
    resp <- probe(marker_url); probed <- marker_url
  }

  if (inherits(resp, "error")) {
    bad("cannot reach ", probed, ": ", conditionMessage(resp),
        "\n           -> check the URL, your network, and whether the server needs a VPN")
  } else {
    st <- httr2::resp_status(resp)
    if (st == 200 && probed == health_url) ok("server up, API key accepted (", health_url, " -> 200)")
    else if (st == 405) ok("endpoint reachable, API key accepted (405 = POST-only, expected)")
    else if (st == 401 && nzchar(api_key)) bad("401 Unauthorized -- MY_SERVER_IVR_API_KEY was rejected",
        "\n           -> check for typos, and that the key has not been revoked in Open WebUI")
    else if (st == 401) bad("401 Unauthorized -- the server requires an API key and none is set",
        "\n           -> add MY_SERVER_IVR_API_KEY to ~/.Renviron")
    else if (st == 404) bad("404 Not Found -- MARKERSYNC_URL is wrong (it must end in /marker/upload)")
    else if (st == 503) bad("503 -- the server cannot validate API keys right now (Open WebUI",
        " backend unreachable). Server-side; retry later")
    else if (st >= 500) bad("server error ", st, " -- the Marker server itself is unhealthy")
    else ok("endpoint reachable (HTTP ", st, ")")
  }
} else if (!nzchar(marker_url)) {
  warn("skipped -- MARKERSYNC_URL not set")
}

# --- Verdict ---------------------------------------------------------------
cat("\n", strrep("-", 60), "\n", sep = "")
if (length(problems) == 0) {
  cat("All checks passed. Run: Rscript -e 'markersync::sync_fulltext()'\n")
  quit(status = 0)
} else {
  cat(length(problems), " problem(s) found -- see [FAIL] lines above.\n", sep = "")
  quit(status = 1)
}
