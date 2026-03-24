---
name: knap
description: >-
  Manage project knowledge in the Knap vault using CLI commands. Use when:
  (1) finishing a coding session and need to record what was done,
  (2) completing or adding TODOs for a project,
  (3) logging changes or decisions,
  (4) user says "ship", "review", "knap", or asks to update project docs,
  (5) scaffolding a new project into the vault.
  NOT for: general file editing, git operations, or deployment.
---

# Knap — Project Knowledge CLI

Knap tracks project status, plans, and logs in markdown files. The developer drives updates via CLI commands; AI sessions read the files for context.

## Vault Structure

Each project lives at `Projects/<Name>/` in the vault with four files:

| File | Purpose |
|---|---|
| `STATUS.md` | What the project is, key decisions, known issues |
| `PLAN.md` | TODOs in Now/Next/Later/Done sections |
| `LOG.md` | Changelog entries grouped by date |
| `CONTEXT.md` | Tech stack, key files, conventions, gotchas |

## Commands

All commands auto-detect the project from cwd. Use `-p <Name>` to target a specific project.

### Capture

```bash
# Add a TODO (defaults to Now section)
knap todo "Implement search endpoint"
knap todo --next "Add pagination"
knap todo --later "Performance audit"

# Mark TODOs complete (interactive picker)
knap done

# Log what happened
knap log "Refactored auth to use Sanctum"

# Capture a note/decision/issue
knap note "Using Redis for session storage — Memcached too limited"
```

### Session Flow

```bash
# End-of-session review: mark done → add new todos → write log
knap review

# Pre-deploy: shows remaining todos → review → sync vault
knap ship
```

### Scaffolding

```bash
# Scaffold from cwd (detects stack, seeds from git log)
knap init

# Scaffold empty project by name
knap project MyApp

# Sync vault to git
knap sync
```

## When to Run Commands

- **After completing work**: `knap done` to mark TODOs, `knap log` to record what changed.
- **When user asks to "ship"**: Run `knap ship` (or `knap review` then `knap sync`).
- **When adding tasks**: `knap todo` with the right section flag.
- **When making a decision**: `knap note` to capture the reasoning.
- **Starting a new project**: `knap init` from the project root.

## Reading Project Context

When working on a project, read its vault files for context — don't load all of them upfront:

- **Starting work**: Read `PLAN.md` to see what's open.
- **Need project background**: Read `STATUS.md`.
- **Need technical details**: Read `CONTEXT.md`.
- **Need recent history**: Read `LOG.md`.

The vault path is resolved from the `knap` binary location (the vault is the repo root containing the `knap` script).
