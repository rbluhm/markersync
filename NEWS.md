# markersync 0.3.0

* `pdf_to_md()` now reports **why** a conversion failed. The Marker API
  answers HTTP 200 with `{"success": false, "error": ...}`, and the error
  field was previously discarded, so every server-side failure surfaced as
  the same opaque `Marker conversion failed for <pdf>`. GPU out-of-memory
  responses additionally say that the condition is server-side.
* `pdf_to_md()` warns when only one of `MARKERSYNC_USER` / `MARKERSYNC_PASS`
  is set. Previously the half-configured pair was dropped silently and the
  server answered 401 with nothing pointing at the cause.
* 401 and 404 responses now get named, actionable messages instead of a
  truncated response body.
* Documented `marker_user` / `marker_pass`, and documented basic auth in the
  README, where it had been missing since the feature was added.
* Fixed the `install_github("YOUR-USERNAME/markersync")` placeholder in the
  README.
* Ships an agent skill for Claude Code and Codex under `skills/`, plus
  `doctor.R` (diagnoses every link in the chain) and `convert.R` (standalone
  single-file conversion). The repository doubles as a Claude Code plugin
  marketplace.

# markersync 0.2.0

* `status()` renamed to `sync_status()` for namespace clarity.
* `MARKERSYNC_URL` is now required: removed lab-specific default. The
  package errors with a clear message if neither the env var nor the
  `marker_url` argument is set.
* README and package docs updated for public release.

# markersync 0.1.1

* Fixed PCRE compile error in `extract_pdf_id()`: variable-length
  lookbehinds replaced with line-by-line matching using a capture
  group.
* `extract_pdf_id()` now matches case-insensitively, so `pdf:`,
  `**PDF:**`, etc. all work.

# markersync 0.1.0

* Initial release: `pdf_to_md()`, `sync_fulltext()`, `extract_pdf_id()`,
  `find_zotero_pdf()`, `status()`.
