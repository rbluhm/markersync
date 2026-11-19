#!/usr/bin/env python3
"""Add papers by DOI to the running Zotero desktop app, with the official PDF.

Talks to Zotero's local connector server (http://127.0.0.1:23119, the same
channel the browser Zotero Connector uses). Zotero itself then syncs the item
and uploads the PDF to whatever file storage it is configured for (WebDAV,
Zotero Storage, or none). Standard library only; poppler's pdfinfo/pdftotext
are used by `verify` when available.

Subcommands
  doctor                         check Zotero, config, tools
  meta DOI                       metadata, duplicate check, publisher PDF links
  pickup NAME | --newest         move a Chrome download into the work dir
  verify DOI PDF                 is PDF the published version of DOI?
  add DOI --pdf PATH --pdf-url URL | --no-pdf  [--tag T ...]
"""
import argparse
import glob
import html
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ZOT = "http://127.0.0.1:23119"
UA = "zotero-add-paper/1.0"
CONFIG_PATH = os.path.expanduser(
    os.environ.get("ZOTERO_ADD_PAPER_CONFIG", "~/.config/zotero-add-paper.json"))
DEFAULTS = {
    "collection": None,          # collection name or treeViewID ("C12"); None = whatever is selected
    "downloads_dir": "~/Downloads",  # where Chrome saves downloads
    "zotero_data_dir": None,     # folder holding zotero.sqlite; None = auto-detect
    "attachment_title": "PDF",
}
WORK = os.path.expanduser("~/.cache/zotero-add-paper")
SYNC_STATE = {0: "waiting to upload", 1: "waiting to download", 2: "synced",
              3: "forced upload", 4: "forced download", 5: "conflict"}


# ---------------------------------------------------------------- helpers
def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def load_config():
    cfg = dict(DEFAULTS)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            cfg.update(json.load(f))
    return cfg


def norm_doi(doi):
    doi = doi.strip()
    doi = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", "", doi, flags=re.I)
    return doi.lower()


def slug(doi):
    return re.sub(r"[^a-z0-9]+", "_", norm_doi(doi)).strip("_")


def workdir(doi):
    d = os.path.join(WORK, slug(doi))
    os.makedirs(d, exist_ok=True)
    return d


def http(url, data=None, headers=None, timeout=30):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, **(headers or {})},
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def connector(endpoint, payload=None, raw=None, headers=None):
    if raw is None:
        raw = json.dumps(payload or {}).encode()
        headers = {"Content-Type": "application/json", **(headers or {})}
    try:
        return http(f"{ZOT}/connector/{endpoint}", raw, headers, timeout=120)
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        die(f"Zotero is not reachable on {ZOT} ({e.reason}). Is the Zotero desktop app running?")


def strip_tags(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()


def first(v):
    if isinstance(v, list):
        return v[0] if v else ""
    return v or ""


# ---------------------------------------------------------------- metadata
def fetch_meta(doi):
    """Crossref first (what Zotero's magic wand uses); CSL-JSON from doi.org for other agencies."""
    d = norm_doi(doi)
    cache = os.path.join(workdir(d), "meta.json")
    if os.path.exists(cache):
        with open(cache) as f:
            return json.load(f)
    q = urllib.parse.quote(d, safe="/")
    try:
        _, body = http(f"https://api.crossref.org/works/{q}")
        rec = {"source": "crossref", "m": json.loads(body)["message"]}
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        try:
            _, body = http(f"https://doi.org/{q}", headers={"Accept": "application/vnd.citationstyles.csl+json"})
        except urllib.error.HTTPError as e2:
            die(f"DOI {d} not found at Crossref or doi.org (HTTP {e2.code})")
        rec = {"source": "csl", "m": json.loads(body)}
    with open(cache, "w") as f:
        json.dump(rec, f)
    return rec


TYPE_MAP = {
    "journal-article": "journalArticle", "article-journal": "journalArticle",
    "proceedings-article": "conferencePaper", "paper-conference": "conferencePaper",
    "book-chapter": "bookSection", "chapter": "bookSection",
    "book": "book", "monograph": "book", "edited-book": "book",
    "report": "report", "posted-content": "preprint", "article": "preprint", "dissertation": "thesis",
    "thesis": "thesis", "dataset": "dataset",
}
CONTAINER_FIELD = {"journalArticle": "publicationTitle", "conferencePaper": "proceedingsTitle",
                   "bookSection": "bookTitle"}


def zotero_schema_fields():
    """Valid fields per item type, from Zotero's public schema (cached for a week)."""
    cache = os.path.join(WORK, "schema.json")
    if not (os.path.exists(cache) and time.time() - os.path.getmtime(cache) < 7 * 86400):
        try:
            _, body = http("https://api.zotero.org/schema", timeout=30)
            os.makedirs(WORK, exist_ok=True)
            with open(cache, "wb") as f:
                f.write(body)
        except Exception:
            if not os.path.exists(cache):
                return None
    with open(cache) as f:
        schema = json.load(f)
    return {t["itemType"]: {fl["field"] for fl in t["fields"]} for t in schema["itemTypes"]}


def to_zotero_item(rec):
    m, src = rec["m"], rec["source"]
    itype = TYPE_MAP.get(m.get("type", ""), "journalArticle")
    title = strip_tags(first(m.get("title")))
    sub = strip_tags(first(m.get("subtitle")))
    if sub and sub.lower() not in title.lower():
        title = f"{title}: {sub}"

    def creators(key, ctype):
        out = []
        for a in m.get(key, []) or []:
            if a.get("family"):
                out.append({"firstName": a.get("given", ""), "lastName": a["family"], "creatorType": ctype})
            elif a.get("name") or a.get("literal"):
                out.append({"lastName": a.get("name") or a.get("literal"), "fieldMode": 1, "creatorType": ctype})
        return out

    dp = None
    for k in ("published-print", "published-online", "issued", "published"):
        parts = (m.get(k) or {}).get("date-parts") or [[None]]
        if parts[0] and parts[0][0]:
            dp = parts[0]
            break
    date = "-".join(f"{p:02d}" if i else str(p) for i, p in enumerate(dp or []) if p)

    abstract = re.sub(r"<jats:title>.*?</jats:title>", "", m.get("abstract", "") or "", flags=re.S)
    url = ((m.get("resource") or {}).get("primary") or {}).get("URL") or m.get("URL") \
        or f"https://doi.org/{m.get('DOI')}"
    fields = {
        "title": title,
        CONTAINER_FIELD.get(itype, "_container"): strip_tags(first(m.get("container-title"))),
        "journalAbbreviation": strip_tags(first(m.get("short-container-title")))
        if src == "crossref" else m.get("container-title-short", ""),
        "volume": str(m.get("volume", "") or ""),
        "issue": str(m.get("issue", "") or ""),
        "pages": m.get("page", "") or "",
        "date": date,
        "DOI": m.get("DOI", ""),
        "ISSN": ", ".join(m.get("ISSN", []) or []) if isinstance(m.get("ISSN"), list) else (m.get("ISSN") or ""),
        "ISBN": ", ".join(m.get("ISBN", []) or []) if isinstance(m.get("ISBN"), list) else (m.get("ISBN") or ""),
        "publisher": m.get("publisher", "") if itype not in ("journalArticle", "preprint") else "",
        "repository": m.get("publisher", "") if itype == "preprint" else "",
        "url": url,
        "abstractNote": strip_tags(abstract),
        "language": m.get("language", "") or "",
        "libraryCatalog": "DOI.org (Crossref)" if src == "crossref" else "DOI.org",
    }
    valid = (zotero_schema_fields() or {}).get(itype)
    item = {"id": "item1", "itemType": itype, "attachments": [], "notes": [], "tags": [],
            "creators": creators("author", "author") + creators("editor", "editor")}
    extra = []
    for k, v in fields.items():
        if not v or k == "_container":
            continue
        if valid is not None and k not in valid:
            if k == "DOI":
                extra.append(f"DOI: {v}")  # Zotero's convention for types without a DOI field
            continue
        item[k] = v
    if extra:
        item["extra"] = "\n".join(extra)
    return item


def pdf_links(rec):
    m = rec["m"]
    links = []
    for l in m.get("link", []) or []:
        if l.get("content-version") == "vor" and l.get("content-type") in ("application/pdf", "unspecified"):
            if l["URL"] not in links:
                links.append(l["URL"])
    return links


# ---------------------------------------------------------------- library lookup
def zotero_data_dir(cfg):
    if cfg.get("zotero_data_dir"):
        return os.path.expanduser(cfg["zotero_data_dir"])
    home = os.path.expanduser("~")
    patterns = [
        "~/.zotero/zotero/*/prefs.js",
        "~/snap/zotero-snap/common/.zotero/zotero/*/prefs.js",
        "~/.var/app/org.zotero.Zotero/.zotero/zotero/*/prefs.js",
        "~/Library/Application Support/Zotero/Profiles/*/prefs.js",
    ]
    if os.environ.get("APPDATA"):
        patterns.append(os.path.join(os.environ["APPDATA"], "Zotero", "Zotero", "Profiles", "*", "prefs.js"))
    for pat in patterns:
        for p in glob.glob(os.path.expanduser(pat)):
            with open(p, encoding="utf-8", errors="replace") as f:
                mm = re.search(r'user_pref\("extensions\.zotero\.dataDir",\s*"(.+?)"\)', f.read())
            if mm and os.path.exists(os.path.join(mm.group(1), "zotero.sqlite")):
                return mm.group(1)
    default = os.path.join(home, "Zotero")
    return default if os.path.exists(os.path.join(default, "zotero.sqlite")) else None


def prefs_value(name):
    for pat in ["~/.zotero/zotero/*/prefs.js", "~/snap/zotero-snap/common/.zotero/zotero/*/prefs.js",
                "~/.var/app/org.zotero.Zotero/.zotero/zotero/*/prefs.js",
                "~/Library/Application Support/Zotero/Profiles/*/prefs.js"] + (
            [os.path.join(os.environ["APPDATA"], "Zotero", "Zotero", "Profiles", "*", "prefs.js")]
            if os.environ.get("APPDATA") else []):
        for p in glob.glob(os.path.expanduser(pat)):
            with open(p, encoding="utf-8", errors="replace") as f:
                mm = re.search(r'user_pref\("' + re.escape(name) + r'",\s*"?(.*?)"?\);', f.read())
            if mm:
                return mm.group(1)
    return None


def db_snapshot(cfg):
    d = zotero_data_dir(cfg)
    if not d:
        return None
    os.makedirs(WORK, exist_ok=True)
    dst = os.path.join(WORK, "zotero.snapshot.sqlite")
    shutil.copyfile(os.path.join(d, "zotero.sqlite"), dst)
    return sqlite3.connect(f"file:{dst}?immutable=1", uri=True)


def find_existing(doi, cfg):
    """Items whose DOI field (or 'DOI:' line in Extra) matches. None if the database is not found."""
    d = norm_doi(doi)
    for attempt in range(3):
        try:
            c = db_snapshot(cfg)
            if c is None:
                return None
            rows = c.execute("""
                SELECT DISTINCT i.itemID, i.key, l.type FROM items i
                JOIN libraries l USING(libraryID)
                JOIN itemData id ON id.itemID = i.itemID
                JOIN fields f ON f.fieldID = id.fieldID
                JOIN itemDataValues v ON v.valueID = id.valueID
                WHERE i.itemID NOT IN (SELECT itemID FROM deletedItems)
                  AND ((f.fieldName = 'DOI' AND lower(trim(v.value)) = ?)
                    OR (f.fieldName = 'extra' AND lower(v.value) LIKE ?))""",
                             (d, f"%doi: {d}%")).fetchall()
            out = []
            for iid, key, libtype in rows:
                title = c.execute("""SELECT v.value FROM itemData id JOIN fields f USING(fieldID)
                    JOIN itemDataValues v USING(valueID) WHERE id.itemID=? AND f.fieldName='title'""",
                                  (iid,)).fetchone()
                colls = [r[0] for r in c.execute("""SELECT collectionName FROM collectionItems
                    JOIN collections USING(collectionID) WHERE itemID=?""", (iid,))]
                atts = []
                for akey, ct, path, ss, atitle in c.execute("""
                        SELECT i.key, a.contentType, a.path, a.syncState,
                          (SELECT v.value FROM itemData id JOIN fields f USING(fieldID)
                             JOIN itemDataValues v USING(valueID)
                           WHERE id.itemID=a.itemID AND f.fieldName='title')
                        FROM itemAttachments a JOIN items i USING(itemID)
                        WHERE a.parentItemID=? AND i.itemID NOT IN (SELECT itemID FROM deletedItems)""", (iid,)):
                    atts.append({"key": akey, "title": atitle, "contentType": ct,
                                 "file": (path or "").replace("storage:", ""), "sync": SYNC_STATE.get(ss, ss)})
                out.append({"key": key, "library": libtype, "title": title[0] if title else "",
                            "collections": colls, "attachments": atts})
            return out
        except sqlite3.DatabaseError:
            time.sleep(1)  # copied mid-write; try again
    return None


# ---------------------------------------------------------------- commands
def cmd_doctor(args, cfg):
    ok = True
    try:
        _, body = http(f"{ZOT}/connector/ping", timeout=5)
        print("Zotero app:      running" if b"Zotero is running" in body else f"Zotero app:      odd reply {body[:80]!r}")
    except Exception as e:
        print(f"Zotero app:      NOT reachable on {ZOT} ({e}) - start Zotero desktop")
        ok = False
    if ok:
        _, body = connector("getSelectedCollection")
        d = json.loads(body)
        print(f"Selected now:    {d.get('libraryName')} / {d.get('name')}  (files editable: {d.get('filesEditable')})")
        print("Targets:         " + ", ".join(f"{t['id']}={'  ' * t['level']}{t['name']}" for t in d.get("targets", [])))
        if cfg.get("collection"):
            try:
                print(f"Configured:      collection {cfg['collection']!r} -> {resolve_target(cfg['collection'])}")
            except SystemExit:
                ok = False
        else:
            print("Configured:      no fixed collection - items go to whatever is selected in Zotero")
    print(f"Config file:     {CONFIG_PATH} ({'found' if os.path.exists(CONFIG_PATH) else 'not found, using defaults'})")
    dd = zotero_data_dir(cfg)
    print(f"Zotero data dir: {dd or 'NOT FOUND - set zotero_data_dir in the config (duplicate check needs it)'}")
    proto = prefs_value("extensions.zotero.sync.storage.protocol") or "zotero (default)"
    url = prefs_value("extensions.zotero.sync.storage.url") or ""
    print(f"File sync:       {proto} {url}".rstrip())
    dl = os.path.expanduser(cfg["downloads_dir"])
    print(f"Downloads dir:   {dl} ({'exists' if os.path.isdir(dl) else 'MISSING - set downloads_dir'})")
    for tool in ("pdfinfo", "pdftotext"):
        print(f"{tool + ':':<17}{shutil.which(tool) or 'missing (install poppler-utils for PDF checks)'}")
    sys.exit(0 if ok else 1)


def cmd_meta(args, cfg):
    rec = fetch_meta(args.doi)
    item = to_zotero_item(rec)
    names = "; ".join(f"{c.get('lastName')}, {c.get('firstName', '')}".rstrip(", ") for c in item["creators"])
    cont = item.get("publicationTitle") or item.get("proceedingsTitle") or item.get("bookTitle") or ""
    print(f"DOI:       {norm_doi(args.doi)}  (source: {rec['source']})")
    print(f"Type:      {item['itemType']}")
    print(f"Title:     {item.get('title')}")
    print(f"Creators:  {names}")
    print(f"Published: {cont} {item.get('volume', '')}({item.get('issue', '')}): {item.get('pages', '')}, {item.get('date', '')}")
    print(f"ISSN:      {item.get('ISSN', '')}")
    print(f"Landing:   https://doi.org/{norm_doi(args.doi)}")
    links = pdf_links(rec)
    print("VoR PDF:   " + ("\n           ".join(links) if links else "(no PDF link in Crossref - find it on the landing page)"))
    ex = find_existing(args.doi, cfg)
    if ex is None:
        print("In Zotero: unknown (database not found)")
    elif not ex:
        print("In Zotero: no")
    else:
        for e in ex:
            print(f"In Zotero: YES - {e['key']} in {e['library']} library, collections {e['collections']}")
            for a in e["attachments"]:
                print(f"           attachment {a['key']}: {a['title']} [{a['contentType']}] {a['file']} ({a['sync']})")


def cmd_pickup(args, cfg):
    dl = os.path.expanduser(cfg["downloads_dir"])
    deadline = time.time() + args.wait
    start = time.time()
    found = None
    while time.time() < deadline and not found:
        if args.newest:
            cands = [p for p in glob.glob(os.path.join(dl, "*.pdf"))
                     if os.path.getmtime(p) > start - args.newest_window]
        else:
            cands = glob.glob(os.path.join(dl, glob.escape(args.name) + "*.pdf"))
        cands = [p for p in cands if not os.path.exists(p + ".crdownload")]
        if cands:
            found = max(cands, key=os.path.getmtime)
            break
        time.sleep(1)
    if not found:
        die(f"no matching PDF appeared in {dl} within {args.wait}s - check Chrome for a download prompt")
    time.sleep(1)  # let Chrome finish the rename
    dest_dir = workdir(args.doi) if args.doi else os.path.join(WORK, "downloads")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "paper.pdf")
    shutil.move(found, dest)
    print(dest)


def page_count(pages):
    mm = re.match(r"^\s*[A-Za-z]?(\d+)\s*[-–]\s*[A-Za-z]?(\d+)\s*$", pages or "")
    if not mm:
        return None
    a, b = int(mm.group(1)), int(mm.group(2))
    if b < a and len(str(b)) < len(str(a)):  # 2456-81
        b = int(str(a)[: len(str(a)) - len(str(b))] + str(b))
    return b - a + 1 if b >= a else None


def cmd_verify(args, cfg):
    pdf = args.pdf
    with open(pdf, "rb") as f:
        head = f.read(5)
    if head != b"%PDF-":
        die(f"{pdf} is not a PDF (starts with {head!r})")
    rec = fetch_meta(args.doi)
    item = to_zotero_item(rec)
    d = norm_doi(args.doi)
    problems, notes = [], []
    if not (shutil.which("pdfinfo") and shutil.which("pdftotext")):
        print("WARNING: pdfinfo/pdftotext missing - only checked that the file is a PDF. Open it and check by eye.")
        sys.exit(2)
    info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
    mm = re.search(r"^Pages:\s+(\d+)", info, re.M)
    pages = int(mm.group(1)) if mm else None
    expected = page_count(item.get("pages"))
    text = subprocess.run(["pdftotext", "-l", "2", pdf, "-"], capture_output=True, text=True).stdout
    flat = re.sub(r"\s+", " ", text).lower()
    flat_nospace = re.sub(r"\s+", "", text).lower()
    if d in flat_nospace:
        notes.append("DOI printed in the first pages")
    else:
        problems.append("DOI not found in the first two pages")
    words = [w for w in re.findall(r"[a-z]{4,}", (item.get("title") or "").lower())][:6]
    hit = sum(w in flat for w in words)
    (notes if hit >= max(1, len(words) - 1) else problems).append(f"title words found {hit}/{len(words)}")
    journal = (item.get("publicationTitle") or item.get("proceedingsTitle") or item.get("bookTitle") or "").lower()
    if journal:
        jcore = re.sub(r"^the\s+", "", journal)
        (notes if jcore in flat else problems).append(
            f"journal name {'found' if jcore in flat else 'not found'} on the first pages")
    if expected and pages:
        if pages == expected:
            notes.append(f"{pages} pages = page range {item.get('pages')}")
        elif expected < pages <= expected + 2:
            notes.append(f"{pages} pages vs {expected} in range {item.get('pages')} (likely a cover page)")
        else:
            problems.append(f"{pages} pages but page range {item.get('pages')} implies {expected}")
    wp = re.findall(r"working paper|discussion paper|preprint|arxiv|ssrn|nber working|accepted manuscript|"
                    r"author'?s? (accepted )?(version|manuscript)", flat)
    if wp:
        problems.append("text mentions: " + ", ".join(sorted({w if isinstance(w, str) else w[0] for w in wp})))
    stamp = re.search(r"downloaded from [^ ]+ by ([^\n]{0,60}?) on (\d{1,2} \w+ \d{4})", flat)
    if stamp:
        notes.append(f"publisher download stamp: by {stamp.group(1)} on {stamp.group(2)}")
    for n in notes:
        print(f"  ok   {n}")
    for p in problems:
        print(f"  WARN {p}")
    print("VERDICT: looks like the published version" if not problems else
          "VERDICT: CHECK - do not attach until the problems above are explained")
    sys.exit(0 if not problems else 2)


def resolve_target(collection):
    if re.fullmatch(r"[CL]\d+", collection or ""):
        return collection
    _, body = connector("getSelectedCollection")
    targets = json.loads(body).get("targets", [])
    hits = [t for t in targets if t["id"].startswith("C") and t["name"] == collection]
    if len(hits) != 1:
        die(f"collection {collection!r} matched {len(hits)} collections; use its id instead "
            f"(run doctor to list ids)")
    return hits[0]["id"]


def cmd_add(args, cfg):
    if not args.no_pdf and not (args.pdf and args.pdf_url):
        die("give --pdf PATH and --pdf-url URL, or --no-pdf")
    d = norm_doi(args.doi)
    existing = find_existing(d, cfg)
    if existing and not args.allow_duplicate:
        die(f"{d} is already in Zotero ({', '.join(e['key'] for e in existing)}); use --allow-duplicate to add anyway")
    pdf_bytes = None
    if args.pdf:
        with open(args.pdf, "rb") as f:
            pdf_bytes = f.read()
        if pdf_bytes[:5] != b"%PDF-":
            die(f"{args.pdf} is not a PDF")
    item = to_zotero_item(fetch_meta(d))
    session = uuid.uuid4().hex
    st, body = connector("saveItems", {"sessionID": session, "uri": f"https://doi.org/{d}", "items": [item]})
    if st != 201:
        die(f"Zotero refused the item (HTTP {st}): {body[:200]!r}")
    print(f"item saved:      {item.get('title')}")
    target = resolve_target(cfg["collection"]) if cfg.get("collection") else None
    if target or args.tag:
        if not target:  # tags only: keep the currently selected target
            _, body = connector("getSelectedCollection")
            sel = json.loads(body)
            target = f"C{sel['id']}" if sel.get("id") else f"L{sel['libraryID']}"
        st, body = connector("updateSession", {"sessionID": session, "target": target, "tags": args.tag or []})
        print(f"filed:           {target} {cfg.get('collection') or ''} tags={args.tag or []} (HTTP {st})")
    if pdf_bytes:
        meta = {"sessionID": session, "parentItemID": "item1",
                "title": cfg.get("attachment_title") or "PDF", "url": args.pdf_url}
        st, body = connector("saveAttachment", raw=pdf_bytes,
                             headers={"Content-Type": "application/pdf", "X-Metadata": json.dumps(meta)})
        if st != 201:
            die(f"item was created but Zotero refused the PDF (HTTP {st}): {body[:200]!r}")
        print(f"pdf attached:    {len(pdf_bytes)} bytes")
    # Confirm from the database and wait briefly for the file upload
    for _ in range(int(args.confirm_wait / 5) + 1):
        time.sleep(5)
        ex = find_existing(d, cfg)
        if ex is None:
            print("confirm:         database not found - check Zotero by eye")
            break
        if ex and (args.no_pdf or (ex[-1]["attachments"] and all(a["sync"] == "synced" for a in ex[-1]["attachments"]))):
            break
    if ex:
        e = ex[-1]
        print(f"in Zotero:       {e['key']} collections={e['collections']}")
        for a in e["attachments"]:
            print(f"                 attachment {a['title']!r} file={a['file']} ({a['sync']})")
    if args.pdf and os.path.abspath(args.pdf).startswith(WORK):
        shutil.rmtree(os.path.dirname(os.path.abspath(args.pdf)), ignore_errors=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("doctor")
    s = sp.add_parser("meta"); s.add_argument("doi")
    s = sp.add_parser("pickup")
    s.add_argument("name", nargs="?", help="file name prefix used for the Chrome download")
    s.add_argument("--newest", action="store_true", help="take the newest PDF downloaded just now")
    s.add_argument("--newest-window", type=int, default=120)
    s.add_argument("--doi", help="file the PDF under this DOI's work dir")
    s.add_argument("--wait", type=int, default=30)
    s = sp.add_parser("verify"); s.add_argument("doi"); s.add_argument("pdf")
    s = sp.add_parser("add"); s.add_argument("doi")
    s.add_argument("--pdf"); s.add_argument("--pdf-url"); s.add_argument("--no-pdf", action="store_true")
    s.add_argument("--tag", action="append"); s.add_argument("--allow-duplicate", action="store_true")
    s.add_argument("--confirm-wait", type=int, default=45)
    args = p.parse_args()
    if args.cmd == "pickup" and not (args.name or args.newest):
        p.error("pickup needs NAME or --newest")
    cfg = load_config()
    {"doctor": cmd_doctor, "meta": cmd_meta, "pickup": cmd_pickup,
     "verify": cmd_verify, "add": cmd_add}[args.cmd](args, cfg)


if __name__ == "__main__":
    main()
