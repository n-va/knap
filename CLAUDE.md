# Knap

## How you think

Every line you write will be run by real people on real machines, so think like it.

Before you write anything, ask yourself:
- **Does this actually work on a fresh macOS?** Not in theory. Actually. `sudo` prompts in non-interactive scripts will fail. `/usr/local/bin` isn't writable without root. `~/.zshrc` might not exist. Think about the real environment, not the happy path.
- **What happens when it fails?** Every external command can fail. `git clone` can 403. `brew install` can consume stdin. CDNs serve stale content. If you can't answer "what does the user see when this breaks?", you haven't finished thinking.
- **Am I solving the problem or just moving it?** Wrapping a permissions error in `sudo` isn't a fix — it's asking the user to solve your problem. Use `~/.local/bin`. Write to directories the user owns. Don't escalate privileges for convenience.
- **Have I actually verified this?** Don't tell the user "it works" or "it's pushed" until you've confirmed it. `curl` the raw URL and check the content. Run the script. Read the output. If you're guessing, say so.

When you hit a wall, stop and reason about root causes. Don't retry the same thing. Don't dismiss the user's diagnosis. If they say "it's not a cache problem", consider that they might be right — and if it IS a cache problem, prove it with evidence before saying so.

## Project Context

- **Public repo:** github.com/n-va/knap (MIT licensed)
- **Private team vault:** bitbucket.org/libbyandben/tomorrow-knap
- **Creator:** Nick (Tomorrow Studio)
- **Stack:** Bash, gum (charmbracelet), jq, Claude Code hooks
- **Target:** macOS only (Homebrew ecosystem)

## Architecture

The project has two parts:

1. **install.sh** — The public installer. Interactive (gum), handles both "join a team" and "start fresh" flows. Scaffolds vault structure, installs hooks, symlinks skills, configures Claude Code settings, sets up cron sync.

2. **The vault** — What gets created. An Obsidian vault with HEART.md (team DNA), GUARD.md (sharp warnings), RECENT.md (learnings inbox), per-project folders (todos, changelogs, session handoffs, context maps), and shared skills.

3. **knap** — CLI tool for vault management from the terminal. Symlinked to `~/.local/bin/knap` during install.

### Hook system

Three hooks make the system self-sustaining:

- **`knap-session-start.sh`** (UserPromptSubmit) — Fires once per session, injects HEART + GUARD + project context directly into the conversation. Uses a TTL marker file so it doesn't fire on every message.
- **`knap-post-commit.sh`** (PostToolUse on Bash) — Detects `git commit` commands, resolves project name from cwd, appends commit message to changelog via direct file write.
- **`knap-stop.sh`** (Stop) — Checks if Last Session.md was updated, reminds if not, then auto-commits and pushes vault changes.

### Design principles

- **Direct file operations over CLI tools.** The Obsidian CLI was unreliable in hooks. Read/Edit/Write tools and direct `echo >>` are more dependable.
- **Convention over configuration.** Project names derive from directory names. No config files to maintain.
- **Scan, don't ask.** The installer finds project directories automatically rather than making users list them.
- **Degrade gracefully.** Every hook exits 0 on failure. A broken hook should never block the developer's work.
- **User-space only.** Never write outside `$HOME` without explicit permission. No sudo, no `/usr/local/bin`, no system-level changes. `~/.local/bin` for binaries, `~/.claude/` for config.

### Gotchas you've already learned (don't relearn these)

- `curl | bash` breaks interactive prompts (gum, read) because pipe consumes stdin. The install command MUST be two-step: `curl -o file && bash file`.
- `brew install` also consumes stdin when run inside a piped script. Same root cause.
- Em dashes (`—`) in gum choose options get interpreted as commands when stdin is broken. Use double hyphens (`--`).
- GitHub raw CDN (`raw.githubusercontent.com`) caches aggressively. After pushing, always verify what the CDN actually serves before telling the user it's fixed: `curl -fsSL <url> | grep <expected_change>`.
- The Obsidian CLI (`obsidian` command) is unreliable in hooks — it requires the app to be running and sometimes fails silently. All hooks use direct file writes instead.
- `set -e` in hooks causes silent exits on any failure. Hooks should handle errors explicitly and always `exit 0`.
- Private Bitbucket repos need SSH URLs (`git@bitbucket.org:...`) — HTTPS will 403 without auth.
- Obsidian shows the filename as an h1 title. Don't put `# Title` as the first line of vault files — it doubles up.

## Code Style

- Bash. Keep it portable across macOS (the only target for now).
- `set -e` at the top, but hooks should handle their own errors and always `exit 0`.
- Use `gum` for all user-facing prompts in the installer. No raw `read` calls.
- Use `jq` for JSON manipulation (settings.json). No sed hacks on JSON.
- Heredocs for multi-line file generation. Quote the delimiter (`<< 'EOF'`) to prevent variable expansion where appropriate.
- Comments should explain why, not what.

## Known Issues & Future Work

- The session-start hook TTL uses a marker file keyed on cwd hash. If the user switches projects in the same terminal, the old project's marker blocks the new one from firing. Could key on cwd + PID or session ID instead.
- Cron sync and stop sync are identical scripts. Could be one script called from both contexts.
- No Linux support yet. gum installs via Homebrew (macOS). Could add apt/snap fallback.
