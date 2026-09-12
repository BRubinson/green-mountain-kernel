---
name: gm_maw_fetch
description: "Download web pages into a maw for kbite processing using Playwright"
argument-hint: "<kbite_name> [url axis1 axis2 resource_name | json_manifest]"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, Grep, Task, AskUserQuestion
---

# /gm_maw_fetch {kbite_name}

Downloads web pages into a maw using headless Playwright for JS-rendered content. Supports interactive, inline, and programmatic invocation modes.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Resolve the kbite roots from `gmcc_hook paths --json` (kbite_open_root)
2. Parse `{kbite_name}` from first token of `$ARGUMENTS`
3. Verify maw exists at `{kbite_open_root}/{kbite_name}/`
4. Read MAW_INDEX.md for current state
5. Verify Node.js v18+ is available:
   ```bash
   node --version
   ```
   If missing or <18, error with: `[GMB] Error: Node.js v18+ required. Found: {version or "not found"}`
6. Verify Playwright is installed:
   ```bash
   node -e "require.resolve('playwright')"
   ```
   If fails, error with:
   ```
   [GMB] Error: Playwright not installed

   Install with: npm install playwright
   Then install browsers: npx playwright install chromium
   ```

### If Maw Missing
```
[GMB] Error: No maw found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} first to create the maw.
```
Exit without changes.

---

## Usage Examples

### Interactive (prompts for all parameters)
```
/gm_maw_fetch spatial
```

### Inline (single URL with explicit classification)
```
/gm_maw_fetch spatial https://developer.apple.com/documentation/visionos primary documentation visionos_docs
```

### Programmatic (JSON manifest from /gm_bot*)
```
/gm_maw_fetch spatial {"resources":[{"urls":["https://developer.apple.com/documentation/visionos-release-notes/visionos-2-release-notes","https://developer.apple.com/documentation/visionos-release-notes/visionos-2_1-release-notes"],"axis1":"primary","axis2":"all_others","name":"visionos_release_notes"}]}
```

---

## Argument Parsing and Invocation Modes

Parse remaining `$ARGUMENTS` after `{kbite_name}` to determine mode:

### Mode Detection

- **No additional arguments** -> Interactive Mode
- **Next token starts with `{` or `[`** -> Programmatic Mode (JSON manifest)
- **Next token starts with `http://` or `https://`** -> Inline Mode (positional args)

---

### Interactive Mode

Use AskUserQuestion sequentially:

**Question 1: URLs**
```
Enter the URLs to download (one per line or comma-separated):

- Paste URLs — Enter your URL list
```

**Question 2: Source Authority (Axis 1)**
Use AskUserQuestion:
```
Source authority for these pages?

- primary — Official/first-party source (official docs, vendor pages)
- secondary — Community/third-party source (tutorials, blog posts)
```

**Question 3: Content Type (Axis 2)**
Use AskUserQuestion:
```
Content type?

- documentation — Official docs and guides
- example_project — Code samples or example repos
- api_reference — API/function/library references
- blogs — Blog posts, tutorials, articles
- all_others — Anything else
```

**Question 4: Resource Name**
Use AskUserQuestion:
```
Resource name for this download? (lowercase_with_underscores, max 60 chars)

Default suggestion: {derived from first URL path}

- Use default — {suggested_name}
- Custom name — Enter a custom resource name
```

**URL-to-name derivation**: Extract last meaningful path segment from first URL. Replace hyphens with underscores, strip trailing slashes, lowercase, truncate to 60 chars.
Example: `https://example.com/docs/visionos-2_1-release-notes` -> `visionos_2_1_release_notes`

Build a single resource entry from collected answers.

---

### Inline Mode

```
/gm_maw_fetch {kbite_name} {url} {axis1} {axis2} {resource_name}
```

Parse positional arguments:
- `{url}`: Must start with `http://` or `https://`
- `{axis1}`: Must be `primary` or `secondary`
- `{axis2}`: Must be `documentation`, `example_project`, `api_reference`, `blogs`, or `all_others`
- `{resource_name}`: Lowercase with underscores, max 60 chars

Build a single resource entry.

---

### Programmatic Mode

Accept a JSON manifest as the remaining argument text. Schema:

```json
{
  "resources": [
    {
      "urls": ["https://...", "https://..."],
      "axis1": "primary",
      "axis2": "documentation",
      "name": "resource_name"
    }
  ]
}
```

Each entry in `resources` becomes one crunchable directory containing one or more downloaded pages. Multiple resources are processed sequentially.

---

## Execution

For each resource entry:

### Step 1: Validate

- Verify all URLs start with `http://` or `https://`
- Verify axis1 is `primary` or `secondary`
- Verify axis2 is one of: `documentation`, `example_project`, `api_reference`, `blogs`, `all_others`
- Verify resource_name is non-empty, <=60 chars

### Step 2: Spawn Download Agent

Spawn the download agent via Task tool:

```
Task tool:
  subagent_type: gmcc:gmcc_agent_maw_web_fetch
  model: sonnet
  prompt: |
    Download web pages for kbite "{kbite_name}".

    **Script Path**: $GMCC_PLUGIN_ROOT/scripts/maw_web_fetch.mjs
    **Maw Root**: {kbite_open_root}/{kbite_name}/
    **MAW_INDEX**: {kbite_open_root}/{kbite_name}/MAW_INDEX.md

    Resource to download:
    - Name: {resource_name}
    - URLs: {url_list as JSON array}
    - Axis1: {axis1}
    - Axis2: {axis2}
    - Output Dir: {kbite_open_root}/{kbite_name}/{axis1}/{axis2}/{resource_name}/
```

### Step 3: Collect Results

Read agent results. Track success/failure per resource.

---

## Final Report

```
Maw Fetch Complete: {kbite_name}

**Maw Location**: {kbite_open_root}/{kbite_name}/

## Download Summary

| Resource | Axis | URLs | Status |
|----------|------|------|--------|
| {name} | {axis1}/{axis2} | {count} | success/partial/failed |

## Next Steps

1. Review downloaded content in maw directories
2. Run `/gm_crunch_chew {kbite_name}` to analyze crunchables
```

---

## Error Handling

**Invalid URL:**
```
[GMB] Error: Invalid URL: {url}
Must start with http:// or https://
```

**Invalid axis classification:**
```
[GMB] Error: Invalid classification

axis1 must be: primary | secondary
axis2 must be: documentation | example_project | api_reference | blogs | all_others
```

**Agent spawn failure:**
```
[GMB] Warning: Download agent failed for {resource_name}

Error: {message}

Falling back to direct script execution via Bash.
```

On agent failure, attempt direct execution as fallback:
```bash
# Write manifest to {kbite_open_root}/{kbite_name}/.maw_fetch_manifest.json
# Execute: node $GMCC_PLUGIN_ROOT/scripts/maw_web_fetch.mjs /path/to/manifest.json
# Verify results
# Update MAW_INDEX manually
# Cleanup: rm -f {kbite_open_root}/{kbite_name}/.maw_fetch_manifest.json
```

**All downloads failed:**
```
[GMB] Error: All downloads failed for {resource_name}

Check:
- URLs are accessible
- Network connectivity
- Playwright is installed: npx playwright install chromium
```

**Partial success:**
```
[GMB] Warning: {n}/{total} URLs failed for {resource_name}

Failed URLs:
- {url}: {error}

Successfully downloaded pages are saved and indexed.
```
