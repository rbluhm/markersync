# markersync

R package for syncing Zotero-managed PDFs to Markdown via a self-hosted
[Marker](https://github.com/datalab-to/marker) server.

The typical workflow:

1. You write literature notes in `literature/notes/<citekey>.md`. Each
   note contains a `zotero://select/library/items/<ID>` link to the
   PDF — Zotero plugins like Notero or Better Notes emit these by
   default.
2. You run `sync_fulltext()`. It finds notes that don't yet have a
   fulltext file, looks up each PDF in your local Zotero storage, and
   sends it to your Marker server. The returned Markdown lands in
   `literature/fulltext/<citekey>.md`, with extracted images decoded
   to `literature/fulltext/figures/<citekey>/`.

## Install

```r
# Directly from GitHub:
remotes::install_github("rbluhm/markersync")

# Or from a local tarball:
install.packages("markersync_X.Y.Z.tar.gz", repos = NULL, type = "source")
```

Dependencies (`httr2`, `curl`, `base64enc`) install automatically from CRAN.

> **Re-run the install after every R minor-version upgrade.** R keeps user
> libraries per minor version (`~/R/<platform>/4.5`, `.../4.6`), so upgrading
> R hides packages installed under the previous version rather than migrating
> them. The symptom is `there is no package called 'markersync'` on a machine
> where it was working yesterday.

## Configuration

Add to `~/.Renviron` (one-time, per machine):

```
ZOTERO_STORAGE=/Users/yourname/Zotero/storage
MARKERSYNC_URL=https://your-marker-server.example.com/marker/upload
MY_SERVER_IVR_API_KEY=sk-...
```

Restart R for changes to take effect. The `MARKERSYNC_URL` must point at
a running Marker API endpoint — see
[datalab-to/marker](https://github.com/datalab-to/marker) for setup.

`MY_SERVER_IVR_API_KEY` is your **personal Open WebUI API key**. Create it in
the Open WebUI instance that fronts your Marker server, under *Settings →
Account → API keys*; it is the same key you would use for that instance's
chat-completions API. The package sends it as `Authorization: Bearer <key>`
on every request. Revoking the key in Open WebUI revokes Marker access too.
Leave it unset only if your server needs no authentication at all.

Two things that catch people out:

- `~/.Renviron` **overrides** variables inherited from the shell, so
  `MY_SERVER_IVR_API_KEY=other Rscript ...` will not do what you expect. To
  override for a single run, use `R_ENVIRON_USER=/path/to/alt.Renviron Rscript ...`.
- `ZOTERO_STORAGE` is the `storage` folder inside Zotero's data directory,
  shown under *Settings → Advanced → Files and Folders*. On a snap install it
  is `~/snap/zotero-snap/common/Zotero/storage`; on flatpak,
  `~/.var/app/org.zotero.Zotero/data/Zotero/storage`.

## Usage

The expected layout:

```
project/
└── literature/
    ├── notes/         # one .md per paper, named by citekey,
    │                  # containing a zotero://select/library/items/ID link
    └── fulltext/      # populated by sync_fulltext()
```

Then:

```r
library(markersync)

sync_status()                   # show what's missing
sync_fulltext()                 # convert anything without fulltext
sync_fulltext(force_ocr = TRUE) # re-convert with forced OCR (scanned PDFs)
sync_fulltext(force = TRUE)     # re-convert everything
```

Convert a single PDF directly without going through the notes flow:

```r
pdf_to_md("some-paper.pdf", cite_key = "smith2024")
pdf_to_md("scanned.pdf",    force_ocr = TRUE)
pdf_to_md("long-paper.pdf", page_range = "0-9")  # first 10 pages
```

## Use it from Claude Code or Codex

This repository doubles as an agent skill, so you can ask Claude Code or Codex
to convert a PDF, sync your literature, or diagnose a failed conversion in
plain language. The skill wraps the package and adds two standalone scripts:
`doctor.R`, which checks every link in the chain and names the fix for each
failure, and `convert.R`, which converts a single file without needing notes,
a vault, or even the R package installed.

**Claude Code** — install as a plugin, which keeps it updatable:

```
/plugin marketplace add rbluhm/markersync
/plugin install markersync@markersync
```

Or copy it in manually, to `~/.claude/skills/` for every project or
`.claude/skills/` inside one repo:

```sh
git clone https://github.com/rbluhm/markersync.git
cp -r markersync/skills/literature-sync ~/.claude/skills/
```

**Codex** — ask Codex to install it, or copy it to `$CODEX_HOME/skills`
(default `~/.codex/skills`), which is the only location Codex reads:

```sh
cp -r markersync/skills/literature-sync ~/.codex/skills/
```

Skills are discovered when a session starts, so restart your session after
installing. Then just ask:

> convert ~/Downloads/smith2024.pdf
> sync my literature
> why did desmet2017 fail to convert?

You can also run the scripts directly, without an agent:

```sh
Rscript skills/literature-sync/scripts/doctor.R          # check the setup
Rscript skills/literature-sync/scripts/convert.R paper.pdf --pages 0-9
```

`convert.R` writes to `~/.cache/markersync/` by default and accepts
`--out DIR`, `--name STEM`, `--pages`, `--ocr`, `--print` and `--head N`. It
needs only `httr2`, `curl` and `base64enc`, so it works on a machine that has
credentials configured but no vault and no markersync install.

The skill also ships the Obsidian note template it expects, at
`skills/literature-sync/assets/paper_note.md`, and a full setup walkthrough at
`skills/literature-sync/references/setup.md`.

## Note format

Each note in `literature/notes/<citekey>.md` should contain a Zotero PDF
link. The package looks for any line containing "pdf" (case-insensitive)
that includes a `zotero://select/library/items/<ID>` URL — for example:

```markdown
- **PDF:** [PDF](zotero://select/library/items/QE88SWIQ)
```

If no such line is found, it falls back to the first
`zotero://select/library/items/<ID>` link anywhere in the file. Most
Zotero note-export plugins (Notero, Better Notes, MD Notes) emit the
standard format above out of the box.

## How PDFs are resolved

Given a Zotero item ID `QE88SWIQ`, the package looks for the PDF at:

```
$ZOTERO_STORAGE/QE88SWIQ/<filename>.pdf
```

The first `.pdf` in that directory is used. This is the default Zotero
storage layout on macOS, Linux, and Windows. If you use Zotero's
"linked attachments" feature with a custom directory, set
`ZOTERO_STORAGE` to point there instead.

## Server-side

This package is a client. You need a running Marker server that exposes
an `/upload` endpoint accepting multipart form-data with a `file` field.
The simplest setup is the Docker image built from
[datalab-to/marker](https://github.com/datalab-to/marker), behind a
reverse proxy with HTTPS.

Authentication is the reverse proxy's job: the client sends
`Authorization: Bearer <key>` and expects the proxy to validate the key
(in our setup, against the personal API keys of an Open WebUI instance on
the same host) before forwarding to Marker. A rejected key should come
back as HTTP 401. If the proxy also exposes `<base>/health`, the skill's
`doctor.R` uses it as its liveness check; otherwise it falls back to a GET
on the upload URL and treats the resulting 405 as "up and authenticated".

The server response shape that markersync expects:

```json
{
  "success": true,
  "format": "markdown",
  "output": "# Paper title\n\n...",
  "images": {
    "_page_0_Picture_0.jpeg": "<base64>",
    "...": "..."
  },
  "metadata": { ... }
}
```

## License

MIT
