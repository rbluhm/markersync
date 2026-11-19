---
name: zotero-add-paper
description: Add papers to Zotero by DOI (like Zotero's magic wand) and attach the official publisher PDF, fetched through the user's Chrome with their institutional or society access. Use when the user gives one or more DOIs or citations and wants them in Zotero, asks to "add this to Zotero", "get the PDF into Zotero", or wants to set this workflow up on another computer.
metadata:
  short-description: DOI -> Zotero item + official PDF
---

# Add papers to Zotero by DOI, with the official PDF

`<skill-dir>` is the folder this SKILL.md was loaded from. All commands use
`python3 -I <skill-dir>/scripts/zotero_paper.py <subcommand>` (call it `ZP` below).

How it works: the script sends the item to the **running Zotero desktop app**
through its local connector server (`127.0.0.1:23119`, the channel the browser
Zotero Connector uses). Zotero then syncs the item and uploads the PDF to
whatever file storage it already uses (WebDAV, Zotero Storage). Nothing is
written to the sync folder directly, and no Zotero API key is needed.

## Rules

1. **Official PDF only.** Attach only the publisher's version of record. Never
   a working paper, preprint, accepted manuscript or SSRN/NBER/arXiv copy,
   unless the user says so for that paper. A copy of the publisher PDF hosted
   elsewhere is fine **if the user supplies the link** and `verify` passes.
2. **No licensed official PDF -> stop and ask, every time** (also inside a
   batch). Say what you checked (publisher page, library licence) and offer:
   add without PDF (optionally `--tag no-pdf`), the user gives a link/another
   access route, or skip. Do not search for alternative copies on your own.
3. **Logins, CAPTCHAs, interactive challenges are the user's.** If a page asks
   for a login or shows a challenge that does not clear by itself, stop and
   ask the user to do it in Chrome, then continue.
4. **One paper at a time.** Downloads go sequentially, never in parallel;
   publishers block institutions for bulk downloading. For long lists, pause
   every ~20 papers and report progress.
5. Don't add duplicates: `meta` reports items already in Zotero; skip them and
   say so (unless the existing item has no PDF and the user wants one; then
   ask, because the script only creates new items).

## Per paper

1. **Preflight (once per session):** `ZP doctor`. Zotero must be running. It
   shows where items will go (the configured collection, or whatever is
   selected in Zotero) and which tools are missing.
2. **Metadata + duplicate check:** `ZP meta <DOI>`. Shows title, journal,
   pages, Crossref's version-of-record PDF link (if any) and whether the DOI is
   already in Zotero.
3. **Get the PDF through Claude in Chrome** (load the `chrome-browser` skill
   first; open your own tab). Publisher sites block scripted downloads, so the
   download must happen inside the user's Chrome:
   - Open the VoR PDF link from `meta` in the tab. If there is none, open
     `https://doi.org/<DOI>` and find the publisher's PDF link on the page.
     Check `references/publishers.md` for known quirks.
   - Run this in the tab once it shows the PDF (`javascript_tool`). It
     re-fetches the PDF from the page's own origin and saves it into the
     downloads folder under a known name:
     ```js
     const fname = 'zap_<DOI slug>.pdf';
     const r = await fetch(location.href, {credentials: 'include'});
     const b = await r.blob();
     const head = new TextDecoder().decode(await b.slice(0, 5).arrayBuffer());
     if (r.ok && head === '%PDF-') {
       const a = document.createElement('a');
       a.href = URL.createObjectURL(b); a.download = fname;
       document.body.appendChild(a); a.click(); a.remove();
     }
     ({status: r.status, size: b.size, head, page: location.href, contentType: document.contentType})
     ```
     If `head` is not `%PDF-`, the tab is not showing the PDF (no access,
     landing page, or a challenge): take a screenshot and look. If the page
     says no access, check the library licence (below) and then apply rule 2.
   - Pick it up: `ZP pickup zap_<DOI slug> --doi <DOI>` prints the PDF's new
     path. If Chrome saved the file under the server's name instead (it is set
     to download PDFs rather than open them), use `ZP pickup --newest --doi <DOI>`.
     If nothing appears, screenshot Chrome: it may be showing a download
     prompt ("ask where to save" or "multiple downloads") for the user to answer.
   - Close your tab when done with the paper.
4. **Verify:** `ZP verify <DOI> <pdf>` checks the DOI, title and journal name
   on the first pages, the page count against the page range, and flags
   working-paper wording. Exit 0 = attach. Exit 2 = look at the warnings; old
   scanned PDFs often lack a DOI or have an extra cover page, which is fine if
   the rest matches. Never attach a PDF you could not reconcile.
5. **Add:** `ZP add <DOI> --pdf <path> --pdf-url <the PDF URL>`
   (or `--no-pdf` when the user chose that, plus `--tag no-pdf` if they want).
   The script files the item into the configured collection, attaches the PDF
   with title "PDF" (Zotero renames the file with its own naming rule), waits
   until Zotero reports the file synced, and deletes its working copy.
6. Report per paper: item, collection, PDF filename, sync state. In a batch,
   give one summary table at the end, including skipped duplicates.

## Library licence check (when the publisher says no access)

For German-speaking institutions, the EZB recognises the institution by IP:
open `https://ezb.ur.de/searchres.phtml?jq_type1=IS&jq_term1=<ISSN>&lang=en`
in Chrome, open the details of the entry for current volumes, and read
"Online Availability". Elsewhere use the library's e-journal list. JSTOR
usually has only older volumes (moving wall).

## Configuration

Optional JSON file `~/.config/zotero-add-paper.json` (path can be overridden
with `ZOTERO_ADD_PAPER_CONFIG`):

```json
{"collection": "Inbox", "downloads_dir": "~/Downloads"}
```

- `collection`: collection name (or id like `C12`, see `doctor`). If unset,
  items go wherever Zotero currently has selected.
- `downloads_dir`: Chrome's download folder.
- `zotero_data_dir`: only if `doctor` cannot find `zotero.sqlite`.
- `attachment_title`: default `"PDF"`.

Setting up another computer or another person: `references/setup.md`.
