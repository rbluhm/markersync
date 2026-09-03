# First-time setup

Do these in order. Steps 1-3 are per machine; step 4 is per vault/project.
Stop and run the doctor after each block if something looks off.

## 0. What you need from the lab

Ask whoever runs the Marker server for:

- the upload URL, ending in `/marker/upload`
- an account on the Open WebUI instance that fronts it

Then create your own API key in Open WebUI: *Settings -> Account -> API
keys*. It starts with `sk-`. This is a personal key — do not share it, and
do not use someone else's. If it ever leaks, revoke it in the same place;
that cuts Marker access within a minute.

## 1. R side

Requires R >= 4.1.

```r
install.packages("remotes")
remotes::install_github("rbluhm/markersync", upgrade = "never")
```

Dependencies (`httr2`, `curl`, `base64enc`) come along automatically.

> **Re-run this line after every R minor-version upgrade.** R keeps user
> libraries per minor version (`~/R/<platform>/4.5`, `.../4.6`), so upgrading
> 4.5 -> 4.6 silently hides every package you installed. The symptom is
> `there is no package called 'markersync'`.

## 2. Credentials in ~/.Renviron

`~/.Renviron` is read by every R session at startup. Create or append (no
quotes needed, no spaces around `=`):

```
ZOTERO_STORAGE=/home/you/Zotero/storage
MARKERSYNC_URL=https://your-server.example.edu/marker/upload
MY_SERVER_IVR_API_KEY=sk-...
```

Restart R afterwards — `.Renviron` is only read at startup.

**This file is a secret store.** It is in the home directory, not a repo,
precisely so it never gets committed. Never copy these three lines into a
project file, a script, or a skill.

If you are upgrading from markersync 0.3 or earlier, delete the old
`MARKERSYNC_USER` and `MARKERSYNC_PASS` lines; basic auth is gone and the
doctor will nag about them.

Finding `ZOTERO_STORAGE` — it is the `storage` folder inside Zotero's data
directory, visible in Zotero under *Settings -> Advanced -> Files and Folders*:

| Install | Path |
|---|---|
| Linux (standard) | `~/Zotero/storage` |
| Linux (snap) | `~/snap/zotero-snap/common/Zotero/storage` |
| Linux (flatpak) | `~/.var/app/org.zotero.Zotero/data/Zotero/storage` |
| macOS | `~/Zotero/storage` |
| Windows | `C:/Users/<you>/Zotero/storage` |

Attachments must be **stored files synced to this machine**, not linked files
or cloud-only stubs. If Zotero shows the PDF but `storage/<KEY>/` has no
`.pdf`, the file has not been downloaded yet.

## 3. Obsidian side

1. Install the **Zotero Integration** plugin (by mgmeyers) from Community
   Plugins, and enable it.
2. Copy `assets/paper_note.md` from this skill into your vault at
   `literature/templates/paper_note.md`.
3. In the plugin settings, add an **Export Format**:
   - Name: `mynote`
   - Output Path: `/literature/notes/{{citekey}}.md`
   - Image Output Path: `/literature/notes/assets/{{citekey}}/`
   - Template File: `literature/templates/paper_note.md`
4. Set **Note Import Folder** to `/literature/notes/`.

The template is not cosmetic. Two things in it are load-bearing:

- `- **PDF:** {{pdfZoteroLink}}` — produces the
  `zotero://select/library/items/<KEY>` link that markersync greps for. Without
  it a note reports `no PDF link` forever.
- The `{% persist "..." %}` blocks — anything you type between
  `%% begin x %%` and `%% end x %%` survives re-importing the note from Zotero.
  Everything outside them is overwritten. Put your own thinking inside them.

The template also sorts Zotero highlight colours into sections (orange =
definitions, magenta = research question, green = design/method, red = results,
purple = mechanism, blue = contribution, grey = further literature). Adjust the
colour mapping to your own annotation habits; it changes nothing downstream.

## 4. Per vault

```sh
mkdir -p literature/notes literature/fulltext literature/templates
```

Decide whether `literature/fulltext/` is committed. It is generated, contains
one Markdown file plus a folder of extracted images per paper, and grows fast.
Add to `.gitignore` if you would rather regenerate it:

```
literature/fulltext/
```

## 4b. Installing the skill itself

The skill is harness-agnostic; only the install location differs.

- **Claude Code** — `/plugin marketplace add rbluhm/markersync` then
  `/plugin install markersync@markersync`, or copy the directory to
  `~/.claude/skills/literature-sync` (personal) or `.claude/skills/` (per repo).
- **Codex CLI** — ask Codex to install it, or copy the directory to
  `~/.codex/skills/literature-sync`. Codex reads the same `SKILL.md` format but
  only from `$CODEX_HOME/skills`, so there is no per-repo variant.

## 5. Verify

```sh
Rscript .claude/skills/literature-sync/scripts/doctor.R
```

All five sections should be `[ok]`. Then import one paper from Zotero in
Obsidian (Command palette -> *Zotero Integration: mynote*), and:

```sh
Rscript -e 'markersync::sync_status()'    # should show 1 note, 1 missing
Rscript -e 'markersync::sync_fulltext()'  # should print a checkmark
```

## Daily use, once set up

1. Read and highlight the PDF in Zotero.
2. In Obsidian, run *Zotero Integration: mynote* and pick the item. The note
   appears at `literature/notes/<citekey>.md` with your annotations sorted by
   colour.
3. Ask Claude to "sync my literature", or run
   `Rscript -e 'markersync::sync_fulltext()'`.
4. The fulltext lands at `literature/fulltext/<citekey>.md`, ready to be read,
   quoted, or fed to Claude alongside the note.
