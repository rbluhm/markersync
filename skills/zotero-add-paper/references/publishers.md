# Publisher notes

Known quirks when fetching the official PDF through Claude in Chrome. Add a
line whenever a new publisher behaves unexpectedly.

| Publisher / host | What happens | What works |
|---|---|---|
| MIT Press Direct (`direct.mit.edu`, e.g. REStat) | Cloudflare check on first visit; in the user's Chrome it cleared by itself after a few seconds. Plain curl gets 403. No-access pages redirect to `article-abstract/...?redirectedFrom=fulltext` and say "You do not currently have access". | Wait ~3 s after the check, then work in the tab. Many institutions license only some MIT Press journals; check the library licence before concluding there is no route. |
| AEA (`www.aeaweb.org`, AER etc.) | The article page's "Download Full Text PDF" link (`/articles/pdf/doi/...`) redirects to `pubs.aeaweb.org/doi/pdfplus/...`. A fetch from the `www` page fails because of the cross-site redirect. Older AER articles show "(Complimentary)" without login. | Open the `www` PDF link in the tab first, then run the download snippet on the `pubs.aeaweb.org` page. Papers that need an AEA member login: the user logs in themselves. |
| Harvard project sites (`*.hsites.harvard.edu`) | Akamai blocks curl (403 "Access Denied"). | Open any page on the same site in Chrome, then fetch the PDF URL from there (same origin). |

General pattern: when a fetch fails with "Failed to fetch", the PDF lives on a
different host than the page. Open the PDF URL itself in the tab and run the
snippet there; it fetches `location.href`, which is always the same origin.
