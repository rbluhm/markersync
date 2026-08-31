## {{title | replace('"', "'") }}

- **Authors:** {% for c in creators %}{{c.firstName}} {{c.lastName}}{% if not loop.last %}; {% endif %}{% endfor %}
- **Year:** {{date | format("YYYY")}}
- **Journal:** {% if publicationTitle %}{{publicationTitle | replace('"', "'") }}{% elseif genre and repository %}{{genre | replace('"', "'") }} ({{repository | replace('"', "'") }}){% elseif genre and libraryCatalog %}{{genre | replace('"', "'") }} ({{libraryCatalog | replace('"', "'") }}){% elseif genre %}{{genre | replace('"', "'") }}{% elseif itemType == 'preprint' %}Working Paper{% endif %}

### Zotero / Links
- **Collection:** {% if collections and collections.length > 0 %}{% for c in collections %}{{c.fullPath}}{% if not loop.last %}; {% endif %}{% endfor %}{% endif %}
- **Zotero tags:** {% if allTags %}{{allTags | replace('"', "'") }}{% elseif tags and tags.length > 0 %}{% for t in tags %}{{t.tag}}{% if not loop.last %}, {% endif %}{% endfor %}{% endif %}
- **Zotero item:** [Open item]({{desktopURI}})
- **PDF:** {{pdfZoteroLink}}

### Abstract
{% if abstractNote %}
{{abstractNote}}
{% endif %}

## Persistent notes

### Why this paper matters
{% persist "why-paper-matters" %}
- 
{% endpersist %}

### Important contribution to my project
{% persist "project-contribution" %}
- 
{% endpersist %}

### Further Thoughts
{% persist "thoughts" %}
- 
{% endpersist %}

## In-text annotations
{% set defs = annotations | filterby("colorCategory", "startswith", "Orange") | filterby("type", "contains", "highlight") %}
{% if defs.length > 0 %}
### <span style="color:#f19837;">Definitions</span>
{% for annotation in defs %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set rq = annotations | filterby("colorCategory", "startswith", "Magenta") | filterby("type", "contains", "highlight") %}
{% if rq.length > 0 %}
### <span style="color:#e56eee;">Research question</span>
{% for annotation in rq %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set method = annotations | filterby("colorCategory", "startswith", "Green") | filterby("type", "contains", "highlight") %}
{% if method.length > 0 %}
### <span style="color:#5fb236;">Design / Method</span>
{% for annotation in method %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set results = annotations | filterby("colorCategory", "startswith", "Red") | filterby("type", "contains", "highlight") %}
{% if results.length > 0 %}
### <span style="color:#ff6666;">Results</span>
{% for annotation in results %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set mechanism = annotations | filterby("colorCategory", "startswith", "Purple") | filterby("type", "contains", "highlight") %}
{% if mechanism.length > 0 %}
### <span style="color:#a28ae5;">Mechanism</span>
{% for annotation in mechanism %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set contrib = annotations | filterby("colorCategory", "startswith", "Blue") | filterby("type", "contains", "highlight") %}
{% if contrib.length > 0 %}
### <span style="color:#2ea8e5;">Contribution</span>
{% for annotation in contrib %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}

{% set lit = annotations | filterby("colorCategory", "startswith", "Gray") | filterby("type", "contains", "highlight") %}
{% if lit.length > 0 %}
### <span style="color:#aaaaaa;">Further literature</span>
{% for annotation in lit %}- {{annotation.annotatedText | safe}} — [p. {{annotation.pageLabel}}](zotero://open-pdf/library/items/{{annotation.attachment.itemKey}}?page={{annotation.pageLabel}}&annotation={{annotation.id}}){% if annotation.comment %} — **Comment:** {{annotation.comment | safe}}{% endif %}
{% endfor -%}
{% endif -%}