---
name: project
description: "Identity spine: project, instance, session"
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_session
---

## Project, Instance, Session — Identity Spine

**PROJECT** — One git repository, named by its root basename.

**INSTANCE** — One filesystem checkout of the repository. Moving the checkout mints a NEW INSTANCE. Instance identity derives from absolute repo path.

**SESSION** — One git branch inside an instance. A harness session binds to exactly one.

### All Three Are Derived, Never Guessed
Re-derivable from working directory and branch. Starting in the same repo on the same branch always lands on the same project/instance/session row — existing uuids reused, new rows created only when evidence requires.

### Session State Ensured at Boot
The SessionStart hook upserts project, instance, and session rows and creates the session's artifact home (`prompts/`), idempotently — never clobbering existing state. The harness runs it; an agent never does. If a session boots without its rows, restart the session rather than reaching for the binary.
