# Troubleshooting

Run `scripts/doctor.R` first; it covers most of this automatically. This file
is for reading the errors it cannot classify.

## Getting the server's real error

`sync_fulltext()` and `pdf_to_md()` collapse any server-side failure into
`Marker conversion failed for <pdf>`. The Marker API answers **HTTP 200 with
`{"success": false, "error": "..."}`**, so the useful text is in the body.
Reproduce the POST directly:

```r
pdf  <- markersync::find_zotero_pdf("<ITEMKEY>", Sys.getenv("ZOTERO_STORAGE"))
req  <- httr2::request(Sys.getenv("MARKERSYNC_URL")) |>
  httr2::req_auth_basic(Sys.getenv("MARKERSYNC_USER"), Sys.getenv("MARKERSYNC_PASS")) |>
  httr2::req_body_multipart(file = curl::form_file(pdf),
                            force_ocr = "false", paginate_output = "false") |>
  httr2::req_timeout(600) |>
  httr2::req_error(is_error = function(r) FALSE)
resp <- httr2::req_perform(req)
str(httr2::resp_body_json(resp)[c("success", "error")])
```

## Failure modes

### `there is no package called 'markersync'`

R was upgraded to a new minor version and the user library moved with it
(`~/R/<platform>/4.5` -> `.../4.6`). Every package installed under the old
version is invisible, not deleted.

```r
remotes::install_github("rbluhm/markersync", upgrade = "never")
```

Do not "fix" this by adding the old library to `.libPaths()` — packages built
against the old R are not guaranteed to load.

### `success: false, error: CUDA out of memory`

Server-side. The Marker GPU is saturated by another job; the message reports
how much of the card is free. **Nothing is wrong with the client** — the same
PDF converts fine once the GPU frees up.

Retry later, or ask the server admin to check what is holding the card. If it
persists across hours, the GPU is genuinely oversubscribed and needs the admin,
not a client-side change.

### HTTP 401 Unauthorized

`MARKERSYNC_USER` / `MARKERSYNC_PASS` are wrong or absent from the R session.
Check they are in `~/.Renviron` and that R was restarted since. Verify what R
actually sees without printing the password:

```r
nzchar(Sys.getenv("MARKERSYNC_USER")); nzchar(Sys.getenv("MARKERSYNC_PASS"))
```

### Shell environment variables appear to be ignored

`~/.Renviron` **overrides** variables inherited from the shell, so
`MARKERSYNC_PASS=other Rscript ...` silently keeps using the value in
`~/.Renviron`. This bites when testing against a second server or reproducing a
credential problem. To override for one run, point R at a different env file:

```sh
R_ENVIRON_USER=/path/to/alt.Renviron Rscript ...
```

### HTTP 405 on a plain GET

Expected and healthy. The upload endpoint is POST-only, so 405 means the URL
and credentials are both good. The doctor uses this as its liveness probe.

### HTTP 404

`MARKERSYNC_URL` is wrong. It must be the full upload path, ending in
`/marker/upload`, not the server root.

### `<citekey>: no Zotero PDF link in note`

`extract_pdf_id()` searches the note for a
`zotero://select/library/items/<KEY>` link, preferring lines containing "pdf".
It found none. Causes, in order of likelihood:

- the Zotero item has no PDF attachment
- the note was written from a template without `{{pdfZoteroLink}}`
- the note was hand-written rather than imported

Fix the Zotero item or the template, then re-import the note. Adding the link
by hand works but will be overwritten on the next import.

### `<citekey>: PDF not found (Zotero ID <KEY>)`

The link resolved but `<ZOTERO_STORAGE>/<KEY>/` has no `.pdf`:

- `ZOTERO_STORAGE` points at the wrong Zotero profile (check *Settings ->
  Advanced -> Files and Folders* in Zotero)
- the attachment is a **linked file**, which lives outside `storage/`
- Zotero has not downloaded the attachment to this machine yet — open the item
  in Zotero and confirm the PDF actually opens
- the key belongs to the parent item rather than the attachment; the note's
  `**PDF:**` line must carry the *attachment* key, and `**Zotero item:**` the
  parent

### Conversion succeeds but the Markdown is empty or garbled

A scanned PDF with no text layer. Re-run that paper with OCR:

```r
markersync::pdf_to_md(pdf, cite_key = "<key>", force_ocr = TRUE)
```

`page_range = "0-20"` limits the work while testing.

### Timeout after 10 minutes

`pdf_to_md(timeout = ...)` defaults to 600 seconds. Book-length PDFs exceed it.
Raise it, or convert in slices with `page_range`.

### Images are missing from the fulltext

`pdf_to_md()` writes images to `<fulltext_dir>/figures/<citekey>/` and rewrites
the Markdown links to point there. If the Markdown shows broken images, check
that folder exists — and that `literature/fulltext/figures/` is not gitignored
on a machine where the files were never generated locally.

## Reading a `sync_fulltext()` result

```r
res <- markersync::sync_fulltext()
res$converted    # succeeded this run
res$no_pdf_link  # note has no zotero:// PDF link
res$pdf_missing  # link fine, file not on disk
res$failed       # reached the server, server said no
```

The printed summary always appears, even when everything failed. Read the
buckets, not the summary line.
