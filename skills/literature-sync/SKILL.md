---
name: literature-sync
description: Convert PDFs to Markdown through a self-hosted Marker server, either one file at a time or as a Zotero -> Obsidian literature workflow. Use when the user wants to read, convert, or extract the text of a PDF; sync or fulltext their literature notes; set this workflow up on a new machine; or diagnose why a conversion failed.
metadata:
  short-description: Convert PDFs to Markdown via Marker
---

# Literature sync (Zotero -> Obsidian -> Marker)

Two ways in. **Converting a single PDF needs nothing but server credentials** —
jump to *Convert one file*. The full literature workflow chains three parts:

1. **Zotero** holds the PDFs. Each attachment lives in
   `<ZOTERO_STORAGE>/<8-char item key>/<file>.pdf`.
2. **Obsidian** (Zotero Integration plugin) writes one note per paper into
   `literature/notes/<citekey>.md`. The note template emits a
   `zotero://select/library/items/<KEY>` link on a line containing "PDF" —
   **that link is the only join key** between the note and the PDF on disk.
3. **markersync** (R package, `rbluhm/markersync`) walks the notes, resolves
   each PDF, POSTs it to a Marker server, and writes
   `literature/fulltext/<citekey>.md` plus `literature/fulltext/figures/<citekey>/`.

Fulltext files are keyed by citekey, so `[[citekey]]` links, the note, and the
fulltext all line up in the vault.

`<skill-dir>` below is the directory this SKILL.md lives in — under Claude Code
that is the installed plugin path or `~/.claude/skills/literature-sync`, under
Codex it is `~/.codex/skills/literature-sync`. Use the path you loaded this file
from. Both scripts are plain Rscript and take no harness-specific arguments.

## Pick the right path

| User says | Do this |
|---|---|
| "convert this PDF", "what does this paper say", a path or a Zotero key | **Convert one file** (below) |
| "sync my literature", "convert the new papers" | **Sync the vault** (below) |
| anything failed, "why didn't X convert" | **Diagnose** (below) |
| "set this up", new machine, new colleague | `references/setup.md` |

## Convert one file

For a one-off conversion in chat, with no Zotero note and no vault involved:

```sh
Rscript <skill-dir>/scripts/convert.R <path-or-ZOTEROKEY>
```

It takes a file path or a bare 8-character Zotero item key, prints a size
report plus the first 40 lines, and writes the Markdown to `~/.cache/markersync/`.

```sh
--pages 0-9    convert a page range only -- use this for a quick look at a long PDF
--ocr          scanned document with no text layer
--print        dump the whole Markdown to stdout
--head N       longer or shorter preview
--out DIR      keep the output somewhere specific
```

### Where to write it

The cache is the default so that a passing question ("what does this paper
say?") does not leave generated files in a repo. It is a default, not a policy:
**when the output is meant to be kept, write it into the project.** `--out`
takes any directory and creates it if needed.

```sh
Rscript <skill-dir>/scripts/convert.R ~/Downloads/smith2024.pdf \
  --out literature/fulltext --name smith2024
```

Write into the project whenever the user names a destination, says to keep or
save it, or is adding a paper to their work rather than asking a question about
it. Only ask if it is genuinely ambiguous.

**Name it by citekey when the destination is `literature/fulltext/`.** The vault
keys everything on citekey, and `sync_status()` compares note stems to fulltext
stems. A file called `Desmet_2017.md` sitting next to a note called
`desmet2017.md` is invisible to the sync: the paper still reports as missing,
and the next `sync_fulltext()` converts it a second time. `--name desmet2017`
prevents that. Extracted images land in `<out>/figures/<name>/`, which is the
same layout `sync_fulltext()` produces, so a hand-placed conversion is
indistinguishable from a synced one.

If the project gitignores `literature/fulltext/` (see `references/setup.md`),
say so when writing there — the user may expect the file to be committed.

**Do not use `--print` on a full paper.** A journal article runs 30-40k tokens.
The default report gives you the character, word and token counts up front —
use them to decide:

- short document, or user wants the whole thing: `--print`
- long document, user asked something specific: read the output file with a
  targeted search rather than loading all of it
- just checking what it is: the default 40-line preview is usually enough

The script needs only `httr2`, `curl` and `base64enc` — not the markersync
package — so it works on a machine that has credentials configured but no
literature vault.

## Sync the vault

Always check first — it is free and tells you what work there is:

```sh
Rscript -e 'markersync::sync_status()'
```

Then convert everything missing:

```sh
Rscript -e 'markersync::sync_fulltext()'
```

`sync_fulltext()` skips any citekey that already has a fulltext file, so it is
safe to re-run. It returns a list with `converted`, `no_pdf_link`,
`pdf_missing`, and `failed`. **Report those four buckets back to the user by
citekey** — a run that converts 0 and fails 3 prints a cheerful summary line,
so never report "done" without reading the buckets.

Useful variants:

```sh
# Re-convert everything, including files that already exist
Rscript -e 'markersync::sync_fulltext(force = TRUE)'

# One paper only, e.g. after fixing its Zotero attachment
Rscript -e 'p <- markersync::find_zotero_pdf("QE88SWIQ", Sys.getenv("ZOTERO_STORAGE"));
            markersync::pdf_to_md(p, cite_key = "desmet2017")'

# A scanned PDF that came out empty or garbled
Rscript -e 'markersync::pdf_to_md("<path>", cite_key = "<key>", force_ocr = TRUE)'
```

Conversion is GPU work on a shared server and takes ~1-5 min per paper, plus
a possible wait of up to ~15 min at the start if the GPU is busy serving LLM
requests (the default timeout is 30 min for that reason). Run it in the
background and report the buckets when it returns; do not poll.

## Diagnose

Run the doctor first. It checks all five links in the chain and never prints
secret values:

```sh
Rscript <skill-dir>/scripts/doctor.R
```

It exits non-zero and prints a `[FAIL]` line with the fix for each broken link.
If the doctor is clean but a specific paper failed, `sync_fulltext()` wraps the
server's real error message. Get it back with a raw POST — see
`references/troubleshooting.md`, which also lists every known failure mode
(stranded R library after an R upgrade, GPU out-of-memory, 401, missing PDF
link, PDF not on disk).

The two you will hit most:

- **`there is no package called 'markersync'`** — an R minor-version upgrade
  (4.5 -> 4.6) moved the user library and left the package behind. Reinstall:
  `Rscript -e 'remotes::install_github("rbluhm/markersync", upgrade = "never")'`
- **`Marker conversion failed for <pdf>`** — this is the server, not the
  client. Almost always `CUDA out of memory` because another job holds the
  GPU. Retry later or ask the server admin; there is nothing to fix locally.

## Rules

- **Never write credentials into a file inside a repository.** `MARKERSYNC_URL`,
  `MY_SERVER_IVR_API_KEY`, and `ZOTERO_STORAGE` belong in `~/.Renviron` only.
  The key is the user's personal Open WebUI API key. When helping with setup,
  tell them to create it themselves (*Settings -> Account -> API keys*) and
  paste it in — do not echo it back, and do not read `~/.Renviron` aloud,
  since it usually holds unrelated API keys too.
- `literature/fulltext/` is machine-generated and often large. Check it is
  either gitignored or deliberately committed before adding files.
- Do not hand-edit files in `literature/notes/`. Obsidian regenerates them from
  Zotero; only the `%% begin ... %%` / `%% end ... %%` persist blocks survive a
  re-import.
