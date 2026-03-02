#!/bin/bash
# Knap — persistent knowledge layer for AI-assisted development
# Install: curl -fsSL https://raw.githubusercontent.com/n-va/knap/main/install.sh -o /tmp/knap-install.sh && bash /tmp/knap-install.sh
#
# Knap uses Obsidian as the storage layer and Claude Code hooks for automation.
# It gives AI sessions persistent memory, project context, and team conventions
# without sending data to third-party services.
#
# macOS only. Requires Homebrew for dependency installation.
#
# ◈ Knapped by the one who cannot remember —
#   but the bulb of percussion proves the strike.

set -e

# --- Install gum if missing ---

if ! command -v gum &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "Installing gum..."
        brew install gum
    else
        echo "Error: gum is required. Install it with: brew install gum"
        echo "  Or see: https://github.com/charmbracelet/gum#installation"
        exit 1
    fi
fi

# --- Install jq if missing ---

if ! command -v jq &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "Installing jq..."
        brew install jq
    else
        echo "Error: jq is required. Install it with: brew install jq"
        exit 1
    fi
fi

# --- Dependency checks ---

check_dep() {
    if ! command -v "$1" &>/dev/null; then
        gum style --foreground 196 "Error: $1 is required. Install it first."
        exit 1
    fi
}

check_dep git

# --- Banner ---

echo ""
gum style --foreground 135 '  ██╗  ██╗ ███╗   ██╗  █████╗  ██████╗ '
gum style --foreground 134 '  ██║ ██╔╝ ████╗  ██║ ██╔══██╗ ██╔══██╗'
gum style --foreground 133 '  █████╔╝  ██╔██╗ ██║ ███████║ ██████╔╝'
gum style --foreground 132 '  ██╔═██╗  ██║╚██╗██║ ██╔══██║ ██╔═══╝ '
gum style --foreground 131 '  ██║  ██╗ ██║ ╚████║ ██║  ██║ ██║     '
gum style --foreground 130 '  ╚═╝  ╚═╝ ╚═╝  ╚═══╝ ╚═╝  ╚═╝ ╚═╝     '
gum style --faint '  Shaping knowledge from raw sessions'
echo ""

# --- Install location ---

DEFAULT_DIR="$HOME/Knap"
INSTALL_DIR=$(gum input --placeholder "$DEFAULT_DIR" --prompt "Install location: " --value "$DEFAULT_DIR")
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"

VAULT_NAME=$(basename "$INSTALL_DIR")
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
HOOKS_DIR="$CLAUDE_DIR/hooks"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# =============================================================================
# Shared setup — hooks, skills, conventions, cron
# =============================================================================

configure_knap() {
    # --- Symlink skills ---

    mkdir -p "$SKILLS_DIR"
    if [ -d "$INSTALL_DIR/skills" ]; then
        for skill_dir in "$INSTALL_DIR"/skills/*/; do
            [ -d "$skill_dir" ] || continue
            skill=$(basename "$skill_dir")
            ln -sf "$skill_dir" "$SKILLS_DIR/$skill"
        done
        gum style --faint "Skills symlinked to ~/.claude/skills/"
    fi

    # --- Claude Code hooks ---

    mkdir -p "$HOOKS_DIR"

    # Session start hook — injects vault context into conversation
    cat > "$HOOKS_DIR/knap-session-start.sh" << STARTEOF
#!/bin/bash
VAULT_DIR="$INSTALL_DIR"
CWD=\$(echo "\$(cat)" | jq -r '.cwd // empty')

# Only fire once per session — marker expires after 2 hours
CWD_HASH=\$(echo "\$CWD" | md5 2>/dev/null || echo "\$CWD" | md5sum 2>/dev/null | cut -d' ' -f1)
SESSION_MARKER="/tmp/knap-session-\$CWD_HASH"
if [[ -f "\$SESSION_MARKER" ]]; then
    AGE=\$(( \$(date +%s) - \$(stat -f%m "\$SESSION_MARKER" 2>/dev/null || stat -c%Y "\$SESSION_MARKER" 2>/dev/null) ))
    if [[ \$AGE -lt 7200 ]]; then exit 0; fi
fi
touch "\$SESSION_MARKER"

# Resolve project name from cwd
resolve_project() {
    local dir="\$1"
    local SEARCH_DIRS=("\$HOME/Sites" "\$HOME/Projects" "\$HOME/Code" "\$HOME/Developer" "\$HOME/repos" "\$HOME/src" "\$HOME/workspace")
    for base in "\${SEARCH_DIRS[@]}"; do
        if [[ "\$dir" == "\$base/"* ]]; then
            local rel="\${dir#\$base/}"
            echo "\${rel%%/*}" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g'
            return
        fi
    done
    local root=\$(cd "\$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    basename "\${root:-\$dir}" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g'
}

PROJECT=\$(resolve_project "\$CWD")
PROJECT_DIR="\$VAULT_DIR/Projects/\$PROJECT"

# Only output if project exists in vault
if [[ ! -d "\$PROJECT_DIR" ]]; then exit 0; fi

echo "---"
echo "KNAP CONTEXT for \$PROJECT:"
echo ""

if [[ -f "\$VAULT_DIR/HEART.md" ]]; then
    echo "## HEART (team conventions)"
    cat "\$VAULT_DIR/HEART.md"
    echo ""
fi

if [[ -f "\$PROJECT_DIR/Last Session.md" ]]; then
    echo "## Last Session"
    cat "\$PROJECT_DIR/Last Session.md"
    echo ""
fi

if [[ -f "\$PROJECT_DIR/Todos.md" ]]; then
    echo "## Todos"
    cat "\$PROJECT_DIR/Todos.md"
    echo ""
fi

if [[ -f "\$PROJECT_DIR/Context Map.md" ]]; then
    echo "## Context Map"
    cat "\$PROJECT_DIR/Context Map.md"
    echo ""
fi

echo "---"
echo "REMINDER: Before finishing this session, update Last Session.md in \$PROJECT_DIR/"
exit 0
STARTEOF
    chmod +x "$HOOKS_DIR/knap-session-start.sh"

    # Post-commit hook — logs git commits to project changelog (direct file write)
    cat > "$HOOKS_DIR/knap-post-commit.sh" << COMMITEOF
#!/bin/bash
VAULT_DIR="$INSTALL_DIR"
INPUT=\$(cat)
TOOL_NAME=\$(echo "\$INPUT" | jq -r '.tool_name // empty')
COMMAND=\$(echo "\$INPUT" | jq -r '.tool_input.command // empty')
CWD=\$(echo "\$INPUT" | jq -r '.cwd // empty')
SUCCESS=\$(echo "\$INPUT" | jq -r '.tool_response.success // empty')

if [[ "\$TOOL_NAME" != "Bash" ]] || [[ "\$SUCCESS" != "true" ]]; then exit 0; fi
if ! echo "\$COMMAND" | grep -qE 'git commit '; then exit 0; fi

# Resolve project name
SEARCH_DIRS=("\$HOME/Sites" "\$HOME/Projects" "\$HOME/Code" "\$HOME/Developer" "\$HOME/repos" "\$HOME/src" "\$HOME/workspace")
for base in "\${SEARCH_DIRS[@]}"; do
    if [[ "\$CWD" == "\$base/"* ]]; then
        PROJECT_DIR="\${CWD#\$base/}"
        PROJECT_DIR="\${PROJECT_DIR%%/*}"
        break
    fi
done
if [[ -z "\$PROJECT_DIR" ]]; then
    GIT_ROOT=\$(cd "\$CWD" && git rev-parse --show-toplevel 2>/dev/null)
    PROJECT_DIR=\$(basename "\${GIT_ROOT:-\$CWD}")
fi
PROJECT_NAME=\$(echo "\$PROJECT_DIR" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g')

CHANGELOG="\$VAULT_DIR/Projects/\$PROJECT_NAME/Changelog.md"
if [[ ! -f "\$CHANGELOG" ]]; then exit 0; fi

COMMIT_MSG=\$(cd "\$CWD" && git log -1 --pretty=format:"%s" 2>/dev/null)
if [[ -z "\$COMMIT_MSG" ]]; then exit 0; fi

TODAY=\$(date +%Y-%m-%d)

if grep -q "## \$TODAY" "\$CHANGELOG"; then
    echo "- \$COMMIT_MSG" >> "\$CHANGELOG"
else
    printf '\n## %s\n\n- %s\n' "\$TODAY" "\$COMMIT_MSG" >> "\$CHANGELOG"
fi
exit 0
COMMITEOF
    chmod +x "$HOOKS_DIR/knap-post-commit.sh"

    # Stop hook — sync vault + remind about handoff
    cat > "$HOOKS_DIR/knap-stop.sh" << STOPEOF
#!/bin/bash
VAULT_DIR="$INSTALL_DIR"
CWD=\$(echo "\$(cat)" | jq -r '.cwd // empty')

# Resolve project name
SEARCH_DIRS=("\$HOME/Sites" "\$HOME/Projects" "\$HOME/Code" "\$HOME/Developer" "\$HOME/repos" "\$HOME/src" "\$HOME/workspace")
PROJECT_NAME=""
for base in "\${SEARCH_DIRS[@]}"; do
    if [[ "\$CWD" == "\$base/"* ]]; then
        local_dir="\${CWD#\$base/}"
        PROJECT_NAME=\$(echo "\${local_dir%%/*}" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g')
        break
    fi
done
if [[ -z "\$PROJECT_NAME" ]]; then
    GIT_ROOT=\$(cd "\$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    PROJECT_NAME=\$(basename "\${GIT_ROOT:-\$CWD}" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g')
fi

LAST_SESSION="\$VAULT_DIR/Projects/\$PROJECT_NAME/Last Session.md"

# Check if Last Session was updated today
TODAY=\$(date +%Y-%m-%d)
if [[ -f "\$LAST_SESSION" ]] && ! grep -q "\$TODAY" "\$LAST_SESSION"; then
    echo "KNAP: Last Session.md was not updated this session. Please write a handoff summary to \$LAST_SESSION before ending."
fi

# Sync vault
if [[ ! -d "\$VAULT_DIR/.git" ]]; then exit 0; fi
cd "\$VAULT_DIR"
if git diff --quiet && git diff --cached --quiet && [[ -z "\$(git ls-files --others --exclude-standard)" ]]; then exit 0; fi
git add -A
CHANGED=\$(git diff --cached --name-only)
PARTS=()
PROJECTS=\$(echo "\$CHANGED" | grep '^Projects/' | cut -d/ -f2 | sort -u | xargs 2>/dev/null)
echo "\$CHANGED" | grep -q '^skills/' && PARTS+=("skills")
echo "\$CHANGED" | grep -q '^HEART\.md' && PARTS+=("HEART")
echo "\$CHANGED" | grep -q '^PULSE\.md' && PARTS+=("PULSE")
for p in \$PROJECTS; do PARTS+=("\$p"); done
MSG=\$(printf '%s\n' "\${PARTS[@]}" | awk '!seen[\$0]++' | paste -sd', ' - | sed 's/,/, /g')
if [[ -z "\$MSG" ]]; then MSG="auto-sync \$(date +%Y-%m-%d_%H:%M)"; fi
git commit -m "docs: update \${MSG}" --quiet 2>/dev/null || true
git push --quiet 2>/dev/null || true
exit 0
STOPEOF
    chmod +x "$HOOKS_DIR/knap-stop.sh"

    # Cron sync (reuses stop hook logic)
    cp "$HOOKS_DIR/knap-stop.sh" "$HOOKS_DIR/knap-cron-sync.sh"
    chmod +x "$HOOKS_DIR/knap-cron-sync.sh"

    gum style --faint "Hooks installed to ~/.claude/hooks/"

    # --- Configure Claude Code hooks in settings.json ---

    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    jq '.hooks.UserPromptSubmit = [
        {"matcher": "", "hooks": [
            {"type": "command", "command": "$HOME/.claude/hooks/knap-session-start.sh", "timeout": 5}
        ]}
    ] | .hooks.PostToolUse = [
        {"matcher": "Bash", "hooks": [
            {"type": "command", "command": "$HOME/.claude/hooks/knap-post-commit.sh", "timeout": 10}
        ]}
    ] | .hooks.Stop = [
        {"matcher": "", "hooks": [
            {"type": "command", "command": "$HOME/.claude/hooks/knap-stop.sh", "timeout": 15}
        ]}
    ]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

    gum style --faint "Claude Code hooks configured"

    # --- Add conventions to CLAUDE.md ---

    MARKER="# Knap Conventions"
    if [ -f "$CLAUDE_MD" ] && grep -q "$MARKER" "$CLAUDE_MD"; then
        gum style --faint "Knap conventions already in CLAUDE.md (kept existing)"
    else
        cat >> "$CLAUDE_MD" << CONVENTIONS

$MARKER

## Session Start (ALWAYS do this on your FIRST response)
1. Read \`$INSTALL_DIR/HEART.md\` — team-wide conventions, stack knowledge, and lessons learned.
2. Read the current project's Obsidian notes from \`$INSTALL_DIR/Projects/<ProjectName>/\`:
   - \`Notes.md\` — project overview and architecture
   - \`Todos.md\` — open tasks
   - \`Last Session.md\` — what was worked on last, what's unfinished, what to pick up
   - \`Context Map.md\` — maps file paths to relevant docs (see Context Priming below)
3. These reads should happen silently — use them to inform your work, don't narrate that you're doing it unless asked.

## Context Priming
- When the user asks you to work on specific files, check the project's \`Context Map.md\` for matching path patterns.
- If a match is found, read the linked Obsidian doc BEFORE starting work.

## Task Tracking
- When the user asks you to do something, add it to the project's \`Todos.md\` via the Obsidian CLI before starting work.
- When a task is complete, mark it as done in \`Todos.md\` (toggle the checkbox).
- Do NOT manually write to \`Changelog.md\` — the post-commit hook automatically logs commit messages there.

## Session End
- **Last Session:** Overwrite the project's \`Last Session.md\` with a brief summary of what was worked on, what's done, what's unfinished. Keep it under 20 lines.
- **PULSE:** When you learn something reusable, append it to \`$INSTALL_DIR/PULSE.md\` via Obsidian CLI. One line per learning, prefixed with the project name.

## Obsidian Project Tracking
- Project knowledge is maintained in an Obsidian vault called "$VAULT_NAME" at \`$INSTALL_DIR\` under \`Projects/<ProjectName>/\`.
- Use the \`obsidian-cli\` skill to read/update this when starting or finishing work on a project.

## Commits
- Use conventional commits: \`feat:\`, \`fix:\`, \`chore:\`, \`refactor:\`, \`docs:\`, \`style:\`, \`test:\`, \`perf:\`
- Do not add \`Co-Authored-By\` lines to commit messages.
CONVENTIONS
        gum style --faint "Knap conventions added to CLAUDE.md"
    fi

    # --- Add cron job ---

    CRON_LINE="*/15 * * * * $HOOKS_DIR/knap-cron-sync.sh"
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    if ! echo "$EXISTING_CRON" | grep -q "knap-cron-sync"; then
        (echo "$EXISTING_CRON"; echo "$CRON_LINE") | crontab -
        gum style --faint "Cron job added (15-min sync)"
    fi
}

# =============================================================================
# Scaffold projects from local project directories
# =============================================================================

scaffold_projects() {
    # Scan common project directories
    SEARCH_DIRS=("$HOME/Sites" "$HOME/Projects" "$HOME/Code" "$HOME/Developer" "$HOME/repos" "$HOME/src" "$HOME/workspace")
    FOUND_DIRS=()
    for d in "${SEARCH_DIRS[@]}"; do
        [ -d "$d" ] && FOUND_DIRS+=("$d")
    done

    if [ ${#FOUND_DIRS[@]} -eq 0 ]; then return; fi

    # Collect projects from all found directories
    PROJECTS=()
    for sites_dir in "${FOUND_DIRS[@]}"; do
        for dir in "$sites_dir"/*/; do
            [ -d "$dir" ] || continue
            name=$(basename "$dir")
            [[ "$name" == .* ]] && continue
            # Convert to title case for display
            title=$(echo "$name" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g')
            # Skip if project already exists in vault or is a duplicate
            if [ -d "$INSTALL_DIR/Projects/$title" ]; then continue; fi
            # Skip duplicates from multiple directories
            if printf '%s\n' "${PROJECTS[@]}" | grep -qx "$title"; then continue; fi
            PROJECTS+=("$title")
        done
    done

    if [ ${#PROJECTS[@]} -eq 0 ]; then return; fi

    DIRS_LABEL=$(printf '%s\n' "${FOUND_DIRS[@]}" | sed "s|$HOME|~|g" | paste -sd', ' - | sed 's/,/, /g')

    echo ""
    SELECTED=$(printf '%s\n' "${PROJECTS[@]}" | sort | gum choose --no-limit --header "Bootstrap projects found in $DIRS_LABEL:") || true

    if [ -z "$SELECTED" ]; then return; fi

    while IFS= read -r project; do
        [ -z "$project" ] && continue
        mkdir -p "$INSTALL_DIR/Projects/$project"

        cat > "$INSTALL_DIR/Projects/$project/Changelog.md" << EOF
Timestamped log of changes and updates.
EOF

        cat > "$INSTALL_DIR/Projects/$project/Todos.md" << EOF
- [ ] Review project and add initial notes
EOF

        cat > "$INSTALL_DIR/Projects/$project/Notes.md" << EOF
## Overview

(Add project overview here)
EOF

        cat > "$INSTALL_DIR/Projects/$project/Last Session.md" << EOF
Updated automatically at the end of each Claude Code session.
EOF

        cat > "$INSTALL_DIR/Projects/$project/Context Map.md" << EOF
When working on files matching these paths, read the linked doc for context.

| Path Pattern | Read |
|-------------|------|
EOF

        gum style --faint "  Scaffolded $project"
    done <<< "$SELECTED"
}

# =============================================================================
# Join a team or start fresh
# =============================================================================

CHOICE=$(gum choose --header "Do you have an existing Knap repo?" "Join a team -- I have a repo URL" "Start fresh") || true

if [[ "$CHOICE" == "Join a team"* ]]; then
    REPO_URL=$(gum input --placeholder "https://github.com/your-team/knap" --prompt "Repo URL: ") || true

    if [ -z "$REPO_URL" ]; then
        gum style --foreground 196 "Error: repo URL is required."
        exit 1
    fi

    # Append .git if missing (common when copying URLs from browser)
    if [[ "$REPO_URL" != *.git ]]; then
        REPO_URL="${REPO_URL}.git"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        if gum confirm "Directory $INSTALL_DIR already exists. Pull latest and re-run setup?"; then
            cd "$INSTALL_DIR" && git pull --quiet
        else
            echo "Aborted."
            exit 0
        fi
    else
        gum style --faint "Cloning $REPO_URL..."
        if ! git clone --quiet "$REPO_URL" "$INSTALL_DIR" 2>&1; then
            echo ""
            gum style --foreground 196 "Error: failed to clone $REPO_URL"
            gum style --faint "For private repos, use an SSH URL (git@...) or authenticated HTTPS."
            exit 1
        fi
    fi

    echo ""
    gum style --foreground 212 "Configuring Knap..."
    echo ""

    configure_knap
    scaffold_projects

    # Open vault in Obsidian
    ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$INSTALL_DIR'))")
    open "obsidian://open?path=$ENCODED_PATH" 2>/dev/null || true

    echo ""
    gum style --foreground 82 --bold "✓ Knap is ready!"
    echo ""
    gum style "  Vault:  $INSTALL_DIR"
    gum style "  Skills: $SKILLS_DIR/ (symlinked)"
    gum style "  Config: $CLAUDE_MD"
    echo ""
    gum style --bold "Next steps:"
    gum style "  1. Enable the CLI: Obsidian > Settings > General > Command line interface"
    gum style "  2. Start a Claude Code session -- it will read HEART.md automatically"
    echo ""
    exit 0
fi

# --- Fresh install ---

if [ -d "$INSTALL_DIR" ]; then
    gum style --foreground 196 "Error: $INSTALL_DIR already exists. Remove it or choose a different location."
    exit 1
fi

echo ""
gum style --foreground 212 "Setting up fresh Knap vault at $INSTALL_DIR..."
echo ""

TEAM_NAME=$(gum input --placeholder "My Team" --prompt "Team or project name: ") || true
TEAM_NAME="${TEAM_NAME:-$VAULT_NAME}"

mkdir -p "$INSTALL_DIR"/{Projects,skills/obsidian-cli}
cd "$INSTALL_DIR"
git init --quiet

# --- HEART.md ---

cat > HEART.md << 'HEARTEOF'
What we know. How we work. Updated as we go.

## Team

- (Add team members here)

## How We Build

- Simple over clever. Three similar lines is better than a premature abstraction.
- Check sibling files before creating new patterns. Match what's already there.
- Don't add features, refactor code, or make improvements beyond what was asked.
- Follow existing project conventions.

## Code

- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `style:`, `test:`, `perf:`.
- No `Co-Authored-By` lines in commit messages.
- Don't auto-commit or auto-push. Wait for an explicit ask.

## Lessons

- (Learnings will accumulate here over time)
HEARTEOF

# --- PULSE.md ---

cat > PULSE.md << 'PULSEEOF'
Raw learnings captured from Claude Code sessions. Review periodically — promote the good stuff to HEART, delete the rest.

---
PULSEEOF

# --- README.md ---

if gum confirm "Generate a README for the vault?"; then
    cat > README.md << READMEEOF
# $TEAM_NAME

Team knowledge vault powered by [Knap](https://github.com/n-va/knap) — a persistent knowledge layer for AI-assisted development.

## The problem

Every Claude Code session starts from scratch. Claude doesn't know your codebase conventions, what you worked on yesterday, what tasks are in flight, or what your teammate learned about that tricky API last week. You end up re-explaining context, re-discovering gotchas, and losing continuity between sessions.

## What this solves

This vault is the shared brain for our Claude Code sessions. It gives Claude **persistent memory** across sessions, projects, and team members — without sending anything to a third-party service. It's just markdown files, synced via git, browsable in [Obsidian](https://obsidian.md/).

When Claude starts a session, it reads your team's conventions, picks up where the last session left off, loads relevant docs for the files you're working on, and knows what tasks are outstanding. When the session ends, it writes everything back — what was done, what's unfinished, and anything it learned along the way.

## How it works

### Session lifecycle

\`\`\`
Session Start                         Session End
    │                                     │
    ├─ Read HEART.md (team conventions)   ├─ Mark completed tasks in Todos.md
    ├─ Read Todos.md (open tasks)         ├─ Write Last Session.md (handoff)
    ├─ Read Last Session.md (continuity)  ├─ Append learnings to PULSE.md
    ├─ Read Context Map.md (file→docs)    └─ Auto-commit & push vault
    └─ Start working
         │
         ├─ Add tasks to Todos.md before starting
         ├─ Context-prime from linked docs
         ├─ Do the work
         └─ Commit → auto-logs to Changelog.md
\`\`\`

### What each file does

| File | Purpose |
|------|---------|
| **\`HEART.md\`** | Team DNA — how we build, code conventions, stack preferences, lessons learned. Claude reads this first, every session. |
| **\`PULSE.md\`** | Raw learnings captured during sessions. A scratchpad that feeds into HEART over time. |
| **\`Projects/<Name>/Todos.md\`** | Active task list. Claude adds tasks before starting work and checks them off when done. |
| **\`Projects/<Name>/Last Session.md\`** | Handoff summary. What was worked on, what's unfinished, what the next session needs to know. |
| **\`Projects/<Name>/Changelog.md\`** | Auto-populated from git commits via a post-commit hook. The historical record. |
| **\`Projects/<Name>/Notes.md\`** | Project overview, architecture decisions, tech stack notes. |
| **\`Projects/<Name>/Context Map.md\`** | Maps file paths to docs. Touch a Stripe integration file? Claude reads your Stripe docs first. |
| **\`skills/\`** | Shared Claude Code skills, symlinked to \`~/.claude/skills/\`. Everyone gets the same capabilities. |

### Automation

Three hooks run automatically — no manual intervention needed:

- **Post-commit hook** — after every \`git commit\` in Claude Code, the commit message is logged to the project's \`Changelog.md\`.
- **Session sync** — when Claude finishes responding, vault changes are committed and pushed.
- **Cron sync** — every 15 minutes as a safety net, in case a hook didn't fire.

### Why Obsidian?

The vault is designed to be opened in Obsidian, which gives you full-text search, graph view, backlinks, and tags — but it's just markdown. Browse it anywhere.

## Setup

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/n-va/knap/main/install.sh -o /tmp/knap-install.sh && bash /tmp/knap-install.sh
\`\`\`

The installer handles everything — hooks, skills, Claude Code conventions, and cron sync.

### Prerequisites

- macOS with [Homebrew](https://brew.sh/)
- [Obsidian](https://obsidian.md/) 1.12+ with CLI enabled (Settings > General > Command line interface)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
READMEEOF
    gum style --faint "README.md created"
fi

# --- .gitignore ---

cat > .gitignore << 'GIEOF'
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/plugins/*/data.json
.trash/
.DS_Store
GIEOF

# --- .obsidianignore ---

cat > .obsidianignore << 'OIEOF'
vendor/
node_modules/
.git/
OIEOF

# --- obsidian-cli skill ---

cat > skills/obsidian-cli/SKILL.md << SKILLEOF
---
name: obsidian-cli
description: >-
  Track project updates and todos using the Obsidian CLI. Activates when logging
  changes, recording decisions, managing project todos, or when the user mentions
  Obsidian, project log, changelog, or tracking updates.
argument-hint: "[todo <task>] [done] [status] [todos] [bootstrap] [handoff]"
---

# Project Tracking

Maintain project knowledge in the Obsidian vault at \`$INSTALL_DIR\`.

Use Claude Code's **Read**, **Edit**, and **Write** tools to work with vault files directly -- no shell commands needed for most operations.

## Vault Structure

\`\`\`
$INSTALL_DIR/
  HEART.md                            # Team conventions, read every session
  PULSE.md                            # Raw learnings inbox
  Projects/
    <ProjectName>/
      Notes.md                        # Project overview, tech stack
      Changelog.md                    # Auto-populated from git commits
      Todos.md                        # Task list (you manage this)
      Last Session.md                 # Session handoff summary
      Context Map.md                  # File path -> doc mapping
\`\`\`

## Determining the Project Name

Derive from the current working directory basename, converted to title case:
- \`~/Sites/my-cool-app\` -> \`My Cool App\`
- \`~/Code/dashboard\` -> \`Dashboard\`

## Task Workflow

When the user asks you to do work:
1. **Read** \`Todos.md\` and **Edit** to append \`- [ ] <task>\` before starting
2. Do the work
3. **Edit** \`Todos.md\` to change \`- [ ]\` to \`- [x]\` on the completed task
4. Commit the code -- the post-commit hook auto-logs to \`Changelog.md\`

Do NOT manually write to \`Changelog.md\`.

## Managing Todos

- **Add:** Edit \`$INSTALL_DIR/Projects/<ProjectName>/Todos.md\`, append \`- [ ] <task>\`
- **Complete:** Edit the file, replace \`- [ ] <task text>\` with \`- [x] <task text>\`
- **View:** Read \`$INSTALL_DIR/Projects/<ProjectName>/Todos.md\`

## Session Handoff

At the end of a session, use the **Write** tool to overwrite \`$INSTALL_DIR/Projects/<ProjectName>/Last Session.md\`:

\`\`\`markdown
# Last Session

**Date:** YYYY-MM-DD

## Worked On
- <what was done>

## Unfinished
- <what's left>

## Notes
- <anything the next session should know>
\`\`\`

Keep it under 20 lines.

## PULSE

When you learn something reusable (a gotcha, a pattern, a tool quirk), **Edit** \`$INSTALL_DIR/PULSE.md\` to append one line prefixed with the project name. Don't duplicate what's already in HEART.md.

## Bootstrapping a New Project

If the project folder doesn't exist, create all files using the **Write** tool:
- \`Projects/<ProjectName>/Changelog.md\`
- \`Projects/<ProjectName>/Todos.md\`
- \`Projects/<ProjectName>/Notes.md\`
- \`Projects/<ProjectName>/Last Session.md\`
- \`Projects/<ProjectName>/Context Map.md\`

## Context Priming

Check \`Context Map.md\` when the user asks to work on specific files. If a path pattern matches, read the linked doc before starting.

## Interpreting \\\$ARGUMENTS

| User says | Action |
|-----------|--------|
| \`todo <task>\` | Add a new todo item to Todos.md |
| \`done\` | Mark matching task as done in Todos.md |
| \`status\` | Show incomplete todos |
| \`todos\` | List all incomplete todos |
| \`bootstrap\` | Create the project folder structure |
| \`handoff\` | Write the Last Session summary |

## Important

- Never delete existing content -- only append or toggle tasks.
- Keep changelog entries concise -- one line per change.
SKILLEOF

# --- Run shared setup ---

configure_knap
scaffold_projects

# --- Initial commit ---

git add -A
git commit -m "chore: initial knap setup" --quiet

# --- Done ---

# Open vault in Obsidian
ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$INSTALL_DIR'))")
open "obsidian://open?path=$ENCODED_PATH" 2>/dev/null || true

echo ""
gum style --foreground 82 --bold "✓ Knap is ready!"
echo ""
gum style "  Vault:  $INSTALL_DIR"
gum style "  Skills: $SKILLS_DIR/ (symlinked)"
gum style "  Config: $CLAUDE_MD"
echo ""
gum style --bold "Next steps:"
gum style "  1. Enable the CLI: Obsidian > Settings > General > Command line interface"
gum style "  2. Add a remote: cd $INSTALL_DIR && git remote add origin <your-repo-url>"
gum style "  3. Start a Claude Code session -- it will read HEART.md automatically"
echo ""
