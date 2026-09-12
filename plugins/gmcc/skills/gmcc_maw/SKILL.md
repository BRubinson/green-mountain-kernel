---
name: gmcc_maw
description: "GMCC Maw Web Fetch - Download web pages into maw directories for kbite processing using headless Playwright. Activated when downloading web content for kbite crunchable workflows."
user-invocable: false
disable-model-invocation: true
---

# GMCC Maw Web Fetch

The maw web fetch system automates downloading web pages into maw crunchable directories. It uses headless Playwright to render JS-heavy pages and saves both HTML and markdown for the kbite chew/digest pipeline.

---

## When to Use

Use `/gm_maw_fetch` when:
- Populating a maw with web-based documentation, blog posts, or API references
- Target pages are JS-rendered (SPAs, dynamic content) that WebFetch cannot fully capture
- Batch downloading multiple pages into a structured maw layout

---

## Prerequisites

Before using maw web fetch:

1. **Open a maw**: Run `/gm_crunch_open_maw {kbite_name}` first
2. **Node.js v18+**: Must be available in PATH
3. **Playwright**: Install with `npm install playwright && npx playwright install chromium`

---

## Invocation Modes

### Interactive (standalone)
```
/gm_maw_fetch {kbite_name}
```
Prompts for URLs, axis classification, and resource naming via AskUserQuestion.

### Inline (power user)
```
/gm_maw_fetch {kbite_name} {url} {axis1} {axis2} {resource_name}
```
Single URL with explicit classification.

### Programmatic (from /gm_bot*)
```
/gm_maw_fetch {kbite_name} {"resources": [{"urls": [...], "axis1": "...", "axis2": "...", "name": "..."}]}
```
JSON manifest for automated batch downloads. Allows multiple resources with multiple URLs each.

---

## Download Pipeline

```
/gm_maw_fetch {kbite}
    │
    ├─ Pre-flight: boot, maw, Node.js, Playwright
    ├─ Collect/parse download parameters
    ├─ For each resource:
    │   ├─ Spawn gmcc:agent:maw_web_fetch (sonnet)
    │   │   ├─ Write manifest JSON
    │   │   ├─ Execute maw_web_fetch.mjs
    │   │   │   ├─ Launch headless Chromium
    │   │   │   ├─ Navigate + wait for JS render
    │   │   │   └─ Save {slug}.html + {slug}.md + _manifest.json
    │   │   ├─ Verify downloads (>1KB)
    │   │   └─ Update MAW_INDEX.md (status: pending)
    │   └─ Report results
    └─ Final summary
```

---

## Output Files

For each downloaded URL, the script saves:

| File | Description |
|------|-------------|
| `{slug}.html` | Full rendered HTML after JS execution |
| `{slug}.md` | Extracted text content as basic markdown |
| `_manifest.json` | Metadata: URLs, timestamps, sizes, errors |

Files are saved to: `{kbite_open_root}/{kbite}/{axis1}/{axis2}/{resource_name}/` (kbite_open_root from `gmcc_hook paths --json`)

---

## Workflow Position

```
/gm_crunch_open_maw {kbite}     # Create empty maw
        │
        ▼
/gm_maw_fetch {kbite}           # Download web pages into maw
        │
        ▼
(manually add more resources)    # Optional: add local files too
        │
        ▼
/gm_crunch_chew {kbite}         # Analyze all resources
        │
        ▼
/gm_crunch_digest {kbite}       # Persist to kbite
```

---

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_maw_fetch {kbite_name}` | Download web pages into maw for kbite processing |

## Agent Reference

| Agent | Purpose |
|-------|---------|
| `gmcc:agent:maw_web_fetch()` | Execute Playwright script, verify downloads, update MAW_INDEX |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Playwright not installed` | Run `npm install playwright && npx playwright install chromium` |
| `Node.js not found` | Install Node.js v18+ from nodejs.org |
| Pages download as empty/tiny files | Site may block headless browsers or require auth |
| Timeout errors | Increase timeout in manifest options or check network |
| `Cannot launch browser` | Run `npx playwright install chromium` to install browser binary |
