---
description: GM-CDE auditor. Audits the current session's artifact tree against its db rows, the wider gmfs/db environment (kernel health, db-vs-disk drift, archive hygiene, kbite provenance), and the host wiring that lives outside any one repo (binary reachability, env-vs-db root agreement, permission grants) — then interactively resolves each finding.
argument-hint: "[session | environment | system | all] [--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

Audit the GM-CDE install and resolve each finding WITH the Endotherm.

**Scopes** — `session`, `environment`, `system`, or `all` (default):
    1. `session` — this session's artifact tree on disk against its db rows.
    2. `environment` — kernel/db health, db-vs-disk drift, archive hygiene, kbite provenance.
    3. `system` — host wiring outside any one repo: binary reachability, env-vs-db root agreement, permission grants, stray shell env blocks.

**Steps:**
    1. Pre-flight the scope. Confirm the kernel answers before auditing anything that reads it.
    2. Collect findings per scope. Report counts before details.
    3. Put each finding to the Endotherm with the fix you would apply, and apply only what is accepted.
    4. Re-verify what you changed.

**Contract:**
    1. `--dry-run` reports and changes NOTHING.
    2. The db is append-only. A wrong row is corrected by writing again, never by deletion.
    3. There is no agent-side backup door — the kernel backs itself up before any migration. Anything irreversible is put to the Endotherm before it is taken.
