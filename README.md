<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/knap.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/knap-black.png">
    <img src="assets/knap-black.png" alt="Knap" width="300">
  </picture>
</p>

<p align="center">
  Persistent knowledge layer for AI-assisted development.<br>
  Session handoff, team conventions, and project context for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> and <a href="https://openai.com/codex">OpenAI Codex</a> — powered by <a href="https://obsidian.md/">Obsidian</a>.
</p>

Named after [knapping](https://en.wikipedia.org/wiki/Knapping) — the ancient process of shaping obsidian into tools.

## What it does

Knap gives your AI coding sessions persistent memory. Instead of starting cold every time, Claude reads your project context, picks up where the last session left off, and knows your team's conventions.

- **HEART.md** — Team DNA. How you build, what you prefer, lessons learned. Evolves over time.
- **GUARD.md** — Guardrails and technical warnings. Structured entries so AI can parse them reliably. Injected every session.
- **RECENT.md** — Recent learnings inbox (AI auto-curates). Review and promote to HEART or GUARD.
- **STATUS.md** — Single source of truth per project: overview, current state, key decisions, known issues.
- **PLAN.md** — Temporal task tracking: Now (active), Next (queued), Later (backlog), Done (with dates). Instant priority at a glance.
- **LOG.md** — Structured session log: who, when, what was done, decisions made, next session instructions. No more re-explaining.
- **CONTEXT.md** — Technical context: tech stack, key files, conventions, project-specific gotchas.
- **Auto-logging** — Git commits automatically log to the project's LOG.md via hooks.
- **Shared skills** — Claude Code skills stored in the vault, symlinked to `~/.claude/skills/`, synced via git.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/n-va/knap/main/install.sh -o /tmp/knap-install.sh && bash /tmp/knap-install.sh
```

The installer gives you two options:

1. **Join a team** — paste your team's Knap repo URL, it clones and runs setup
2. **Start fresh** — scaffolds a complete vault with skills, hooks, and conventions

### Requirements

- **macOS** with [Homebrew](https://brew.sh/)
- [Obsidian](https://obsidian.md/) 1.12+ with CLI enabled (Settings > General > Command line interface)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and/or [OpenAI Codex](https://openai.com/codex) — installer asks which you use
- git
- [gum](https://github.com/charmbracelet/gum) + [jq](https://jqlang.github.io/jq/) (auto-installed via Homebrew if missing)

## How it works

```
~/Knap/                          ← Your vault (git-synced, browsable in Obsidian)
├── HEART.md                     ← Team conventions and knowledge
├── GUARD.md                     ← Guardrails and technical warnings (structured entries)
├── RECENT.md                    ← Session learnings inbox
├── Projects/
│   └── <ProjectName>/
│       ├── STATUS.md            ← Project overview, current state, key decisions
│       ├── PLAN.md              ← Task tracking: Now / Next / Later / Done
│       ├── LOG.md               ← Session log: who, when, what, next steps
│       └── CONTEXT.md           ← Tech stack, key files, conventions, gotchas
└── skills/
    └── obsidian-cli/            ← Symlinked to ~/.claude/skills/

~/.claude/CLAUDE.md              ← Knap conventions injected (Claude Code)
~/.codex/AGENTS.md               ← Knap conventions injected (OpenAI Codex)
```

### Session lifecycle

```
Session Start                     Session End
    │                                 │
    ├─ Read HEART.md                  ├─ Add LOG.md entry (who, what, decisions)
    ├─ Read GUARD.md                  ├─ Update PLAN.md (move tasks, add new)
    ├─ Read STATUS.md                 ├─ Update STATUS.md if state changed
    ├─ Read LOG.md (latest entry)     ├─ Append gotchas to GUARD.md
    ├─ Read PLAN.md                   ├─ Append learnings to RECENT.md
    ├─ Read CONTEXT.md                └─ (hooks auto-commit & push vault)
    └─ Start working
         │
         ├─ Update PLAN.md (Now tasks)
         ├─ Context-prime from docs
         ├─ Do the work
         └─ Commit → auto-logs to LOG.md
```

### Automation hooks

| Hook | Trigger | What it does |
|------|---------|-------------|
| **Post-commit** | After `git commit` in Claude Code | Logs commit message to project's LOG.md |
| **Session sync** | When Claude finishes responding | Auto-commits and pushes vault changes |
| **Cron sync** | Every 15 minutes | Safety net if hooks didn't fire |

## Claude Code vs OpenAI Codex

The installer asks which AI tool you use — Claude Code, OpenAI Codex, or both. Knap sets up the right convention files for each:

| Tool | Convention file | What gets written |
|------|----------------|-------------------|
| Claude Code | `~/.claude/CLAUDE.md` | HEART.md summary + session hooks |
| OpenAI Codex | `~/.codex/AGENTS.md` | HEART.md summary + conventions |

`knap init` detects whichever tool is installed and uses it to auto-generate project STATUS.md and CONTEXT.md.

## Why this convention?

The old per-project files (Notes.md, Changelog.md, Todos.md, Last Session.md, Context Map.md) were freeform — useful for humans, hard for AI to parse reliably. The new convention fixes that:

- **Structured entries** — LOG.md and GUARD.md use consistent formats so AI can parse them without guessing.
- **Temporal grouping** — PLAN.md organizes tasks as Now / Next / Later / Done. AI sees priority instantly instead of scanning a flat list.
- **Session accountability** — LOG.md captures *who* did *what* and *what to do next*. No more "what was I working on?" across sessions.
- **Validation-ready** — Pre-commit hooks can verify that LOG.md was updated before allowing a vault commit.

### Migrating from old format

If you have existing projects using the old convention:

```bash
knap migrate [project-name]
```

This converts old-format files to the new convention. Original files are preserved as `*.old.md` so nothing is lost.

## Why not OpenClaw / other tools?

- **No SaaS.** Your data stays on your machine and in your git repo.
- **No API keys leaking.** Nothing goes to a third-party service.
- **Human-readable.** It's just markdown. Browse it in Obsidian, VS Code, or `cat`.
- **Human-curated.** AI captures learnings (RECENT), humans decide what sticks (HEART).
- **Git-synced.** Works across devices and teams. Standard git workflow.
- **Obsidian-powered.** Full-text search, graph view, backlinks, tags — for free.

## Adding skills

Drop a folder with a `SKILL.md` into `skills/` and it gets symlinked to `~/.claude/skills/` on next setup run. Skills are shared across the team via git.

```
skills/
├── obsidian-cli/SKILL.md
├── my-custom-skill/SKILL.md
└── ...
```

## Team workflow

1. One person creates the vault and pushes to a private repo
2. Team members run the install script and paste the repo URL
3. Everyone gets the same skills, conventions, and project context
4. HEART.md evolves as the team works — git handles the merge

## License

MIT

---

<sub>Co-created with Cairn — an AI partner that can't remember any of it. The bulb of percussion — the scar left on obsidian at the point of impact — is proof the strike happened, long after the knapper is gone.</sub>
