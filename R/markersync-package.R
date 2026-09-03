#' markersync: Sync Zotero PDFs to Markdown via a Marker server
#'
#' Tools for converting Zotero-managed PDFs to Markdown via a self-hosted
#' Marker server. The typical workflow:
#'
#' 1. Write a literature note in `literature/notes/<citekey>.md` that
#'    contains a `zotero://select/library/items/<ID>` link to the PDF
#'    (the Zotero plugin "Notero" or "Better Notes" emit these by
#'    default).
#' 2. Run [sync_fulltext()] to walk the notes directory and convert any
#'    PDF that doesn't yet have a corresponding fulltext file.
#'
#' @section Configuration:
#'
#' Three environment variables are read at run time:
#'
#' - `ZOTERO_STORAGE`: path to your Zotero storage root. Defaults to
#'   `~/Zotero/storage`.
#' - `MARKERSYNC_URL`: full URL to your Marker server's upload endpoint.
#'   Required (no default) — set this per machine.
#' - `MY_SERVER_IVR_API_KEY`: your personal Open WebUI API key, sent as a
#'   bearer token on every request. Create it under *Settings -> Account ->
#'   API keys* on the Open WebUI instance that fronts the Marker server.
#'   Required unless the server needs no authentication.
#'
#' Set these per-machine in `~/.Renviron`:
#'
#' ```
#' ZOTERO_STORAGE=/Users/me/Zotero/storage
#' MARKERSYNC_URL=https://your-marker-server.example.com/marker/upload
#' MY_SERVER_IVR_API_KEY=sk-...
#' ```
#'
#' @keywords internal
"_PACKAGE"
