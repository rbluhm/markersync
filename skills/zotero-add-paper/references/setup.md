# Setting up on another computer (or for another person)

## What has to be on the same machine

Claude Code, the Zotero desktop app and Chrome with Claude in Chrome must all
run **on the same computer**:

- The script talks to Zotero at `127.0.0.1:23119`, which exists only on the
  machine where the Zotero app is running.
- Claude in Chrome connects to Claude Code on the same machine.
- Publisher access follows the machine Chrome runs on: campus IP or VPN,
  institutional sign-in cookies, society logins.

A headless server without a desktop session can't run this. A server with a
remote desktop (e.g. x2go) running Zotero and Chrome can.

## Checklist

1. **Zotero 7 desktop**, signed in to the user's zotero.org account. File sync
   can be anything (WebDAV, Zotero Storage, none). The skill doesn't care,
   because Zotero uploads the PDF itself. The connector server is on by
   default; if `doctor` can't reach it, check that the Zotero browser
   connector works on that machine.
2. **Claude Code** with the **Claude in Chrome** extension connected.
3. **Python 3.8+** (standard library only) and **poppler** for checking PDFs
   (`pdfinfo`, `pdftotext`; Debian/Ubuntu `poppler-utils`, macOS
   `brew install poppler`, Windows: poppler binaries on PATH).
4. Copy this folder to `~/.claude/skills/zotero-add-paper/`.
5. Optional config `~/.config/zotero-add-paper.json`, e.g.
   `{"collection": "Inbox"}`. Without it, items go into whatever collection is
   selected in Zotero.
6. Chrome: leave "Ask where to save each file before downloading" **off**, or
   every PDF will need a click from the user.
7. Run `python3 -I <skill-dir>/scripts/zotero_paper.py doctor`.

## Two machines on one Zotero library

Running the skill on two machines that sync the same library is fine. Avoid
adding the same DOI on both before they have synced, because the duplicate
check only sees what the local Zotero already has.
