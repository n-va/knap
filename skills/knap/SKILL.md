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

Knap tracks project context, plans, and logs in markdown. The developer drives updates via CLI; AI sessions read the files for context.

## Vault Structure

Each project lives at `Projects/<Name>/` with three files:

| File | What it answers | Changes |
|---|---|---|
| `Context.md` | What is this project? Stack, decisions, gotchas | Rarely |
| `Plan.md` | What needs doing? Now/Next/Later/Done | Every session |
| `Log.md` | What happened? Entries by date | Every session |

## Commands

All commands auto-detect the project from cwd. Use `-p <Name>` to target a specific project.

### Capture

```bash
knap todo "Implement search endpoint"          # Add to Now
knap todo --next "Add pagination"              # Add to Next
knap todo --later "Performance audit"          # Add to Later
knap done                                      # Interactive: mark TODOs complete
knap log "Refactored auth to use Sanctum"      # Changelog entry under today
knap note "Using Redis — Memcached too limited" # Decision in Context.md
knap note --gotcha "Cron needs --force on prod" # Gotcha in Context.md
```

### Session Flow

```bash
knap review    # End-of-session: mark done → add new todos → write log
knap ship      # Pre-deploy: shows open todos → review → sync vault
```

### Scaffolding

```bash
knap init      # Scaffold from cwd (detects stack, seeds from git log)
knap project MyApp   # Scaffold empty project by name
knap sync      # Commit & push vault changes
```

## When to Run Commands

- **After completing work**: `knap done` + `knap log`.
- **When user says "ship"**: `knap ship`.
- **When adding tasks**: `knap todo` with section flag.
- **When making a decision**: `knap note` to record reasoning.
- **When hitting a gotcha**: `knap note --gotcha`.
- **New project**: `knap init` from the project root.

## Reading Project Context

Read vault files on-demand — don't load all upfront:

- **Starting work** → `Plan.md` (what's open)
- **Need background** → `Context.md` (stack, decisions, gotchas)
- **Need recent history** → `Log.md` (what changed recently)
