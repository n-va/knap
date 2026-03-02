#!/bin/bash
# Knap — persistent knowledge layer for AI-assisted development
# Install: curl -fsSL https://raw.githubusercontent.com/n-va/knap/main/install.sh -o /tmp/knap-install.sh && bash /tmp/knap-install.sh
#
# Knap uses Obsidian as the storage layer and Claude Code hooks for automation.
# It gives AI sessions persistent memory, project context, and team conventions
# without sending data to third-party services.
#
# macOS only. Requires Homebrew for dependency installation.

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

    # Post-commit hook — logs git commits to project changelog
    cat > "$HOOKS_DIR/obsidian-post-commit.sh" << 'HOOKEOF'
#!/bin/bash
set -e
export PATH="$PATH:/Applications/Obsidian.app/Contents/MacOS"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SUCCESS=$(echo "$INPUT" | jq -r '.tool_response.success // empty')

if [[ "$TOOL_NAME" != "Bash" ]] || [[ "$SUCCESS" != "true" ]]; then exit 0; fi
if ! echo "$COMMAND" | grep -qE 'git commit '; then exit 0; fi

SITES_DIR="$HOME/Sites"
RESOLVED_DIR="$CWD"

if [[ "$RESOLVED_DIR" == "$SITES_DIR/"* ]]; then
    RELATIVE="${RESOLVED_DIR#$SITES_DIR/}"
    PROJECT_DIR="${RELATIVE%%/*}"
else
    GIT_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null)
    PROJECT_DIR=$(basename "${GIT_ROOT:-$CWD}")
fi

PROJECT_NAME=$(echo "$PROJECT_DIR" | sed -E 's/(^|[-_])([a-z])/\U\2/g; s/[-_]/ /g')
HOOKEOF

    # Inject vault name
    echo "VAULT_NAME=\"$VAULT_NAME\"" >> "$HOOKS_DIR/obsidian-post-commit.sh"

    cat >> "$HOOKS_DIR/obsidian-post-commit.sh" << 'HOOKEOF2'
CHANGELOG_PATH="Projects/${PROJECT_NAME}/Changelog.md"

if ! obsidian vault="$VAULT_NAME" read path="$CHANGELOG_PATH" &>/dev/null; then exit 0; fi

COMMIT_MSG=$(cd "$CWD" && git log -1 --pretty=format:"%s" 2>/dev/null)
if [[ -z "$COMMIT_MSG" ]]; then exit 0; fi

TODAY=$(date +%Y-%m-%d)
CURRENT_CONTENT=$(obsidian vault="$VAULT_NAME" read path="$CHANGELOG_PATH" 2>/dev/null)

if echo "$CURRENT_CONTENT" | grep -q "## $TODAY"; then
    obsidian vault="$VAULT_NAME" append path="$CHANGELOG_PATH" content="- ${COMMIT_MSG}\n" &>/dev/null
else
    obsidian vault="$VAULT_NAME" append path="$CHANGELOG_PATH" content="\n## ${TODAY}\n\n- ${COMMIT_MSG}\n" &>/dev/null
fi
exit 0
HOOKEOF2
    chmod +x "$HOOKS_DIR/obsidian-post-commit.sh"

    # Sync hook — auto-commit and push vault changes
    cat > "$HOOKS_DIR/obsidian-sync.sh" << SYNCEOF
#!/bin/bash
set -e
VAULT_DIR="$INSTALL_DIR"
if [[ ! -d "\$VAULT_DIR/.git" ]]; then exit 0; fi
cd "\$VAULT_DIR"
if git diff --quiet && git diff --cached --quiet && [[ -z "\$(git ls-files --others --exclude-standard)" ]]; then exit 0; fi
git add -A
CHANGED=\$(git diff --cached --name-only)
PARTS=()
PROJECTS=\$(echo "\$CHANGED" | grep '^Projects/' | cut -d/ -f2 | sort -u | xargs)
ROOT_FILES=\$(echo "\$CHANGED" | grep -v '/' | xargs)
echo "\$CHANGED" | grep -q '^skills/' && PARTS+=("skills")
echo "\$CHANGED" | grep -q '^HEART\.md' && PARTS+=("HEART")
echo "\$CHANGED" | grep -q '^PULSE\.md' && PARTS+=("PULSE")
for p in \$PROJECTS; do PARTS+=("\$p"); done
for f in \$ROOT_FILES; do
    case "\$f" in
        HEART.md|PULSE.md|.*) ;;
        *) PARTS+=("\$f") ;;
    esac
done
MSG=\$(printf '%s\n' "\${PARTS[@]}" | awk '!seen[\$0]++' | paste -sd', ' - | sed 's/,/, /g')
if [[ -z "\$MSG" ]]; then MSG="auto-sync \$(date +%Y-%m-%d %H:%M)"; fi
git commit -m "docs: update \${MSG}" --quiet 2>/dev/null || true
git push --quiet 2>/dev/null || true
exit 0
SYNCEOF
    chmod +x "$HOOKS_DIR/obsidian-sync.sh"

    # Cron sync (same script)
    cp "$HOOKS_DIR/obsidian-sync.sh" "$HOOKS_DIR/obsidian-cron-sync.sh"
    chmod +x "$HOOKS_DIR/obsidian-cron-sync.sh"

    gum style --faint "Hooks installed to ~/.claude/hooks/"

    # --- Configure Claude Code hooks in settings.json ---

    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    jq '.hooks.PostToolUse = [
        {"matcher": "Bash", "hooks": [
            {"type": "command", "command": "$HOME/.claude/hooks/obsidian-post-commit.sh", "timeout": 10}
        ]}
    ] | .hooks.Stop = [
        {"matcher": "", "hooks": [
            {"type": "command", "command": "$HOME/.claude/hooks/obsidian-sync.sh", "timeout": 15}
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

    CRON_LINE="*/15 * * * * $HOOKS_DIR/obsidian-cron-sync.sh"
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    if ! echo "$EXISTING_CRON" | grep -q "obsidian-cron-sync"; then
        (echo "$EXISTING_CRON"; echo "$CRON_LINE") | crontab -
        gum style --faint "Cron job added (15-min sync)"
    fi
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

mkdir -p "$INSTALL_DIR"/{Projects,skills/obsidian-cli}
cd "$INSTALL_DIR"
git init --quiet

# --- HEART.md ---

cat > HEART.md << 'HEARTEOF'
# HEART

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
# PULSE

Raw learnings captured from Claude Code sessions. Review periodically — promote the good stuff to `HEART.md`, delete the rest.

---
PULSEEOF

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

# Obsidian CLI Project Tracking

Use the Obsidian CLI to maintain project changelogs and todo lists inside the user's Obsidian vault.

## Prerequisites

The Obsidian desktop app must be running. The Claude Code Bash tool does not source ~/.zshrc, so always prefix commands with:

\`\`\`bash
export PATH="\$PATH:/Applications/Obsidian.app/Contents/MacOS"
\`\`\`

## Vault & Structure

- **Vault:** \`$VAULT_NAME\` (at \`$INSTALL_DIR\`)
- **Always pass** \`vault=$VAULT_NAME\` as the first parameter to every \`obsidian\` command.

Directory layout inside the vault:

\`\`\`
Projects/
  <ProjectName>/
    Notes.md           # Project overview, tech stack, architecture
    Changelog.md       # Timestamped log (auto-populated from git commits)
    Todos.md           # Task list for the project
    Last Session.md    # What was worked on last session, what's unfinished
    Context Map.md     # Maps file paths to relevant docs for auto-priming
    *.md               # Additional docs (integrations, bugs, etc.)
\`\`\`

## Determining the Project Name

Derive the project name from the current working directory. If the project is under ~/Sites/, use the first directory after ~/Sites/. Otherwise, use the git root basename. Convert to title case.

## Bootstrapping a New Project

\`\`\`bash
obsidian vault=$VAULT_NAME create path="Projects/<ProjectName>/Changelog.md" content="# <ProjectName> Changelog\n\nTimestamped log of changes and updates.\n"
obsidian vault=$VAULT_NAME create path="Projects/<ProjectName>/Todos.md" content="# <ProjectName> Todos\n\n- [ ] Review project and add initial notes\n"
obsidian vault=$VAULT_NAME create path="Projects/<ProjectName>/Notes.md" content="# <ProjectName>\n\n## Overview\n\n(Add project overview here)\n"
obsidian vault=$VAULT_NAME create path="Projects/<ProjectName>/Last Session.md" content="# Last Session\n\nUpdated automatically at the end of each Claude Code session.\n"
obsidian vault=$VAULT_NAME create path="Projects/<ProjectName>/Context Map.md" content="# Context Map\n\nWhen working on files matching these paths, read the linked doc for context.\n\n| Path Pattern | Read |\n|-------------|------|\n"
\`\`\`

## Task Workflow

When the user asks you to do work:
1. Add the task(s) to \`Todos.md\` before starting
2. Do the work
3. Mark the task as done in \`Todos.md\` when complete
4. Commit the code -- the post-commit hook automatically logs the commit message to \`Changelog.md\`

Do NOT manually write to \`Changelog.md\`. The changelog is populated automatically from git commits.

## Managing Todos

### Adding a Todo

\`\`\`bash
obsidian vault=$VAULT_NAME append path="Projects/<ProjectName>/Todos.md" content="- [ ] <task description>\n"
\`\`\`

### Completing a Todo

\`\`\`bash
obsidian vault=$VAULT_NAME tasks path="Projects/<ProjectName>/Todos.md" todo verbose
obsidian vault=$VAULT_NAME task path="Projects/<ProjectName>/Todos.md" line=<n> done
\`\`\`

## Session Handoff

At the end of a session, overwrite \`Last Session.md\`:

\`\`\`bash
obsidian vault=$VAULT_NAME write path="Projects/<ProjectName>/Last Session.md" content="# Last Session\n\n**Date:** \$(date +%Y-%m-%d)\n\n## Worked On\n- <what was done>\n\n## Unfinished\n- <what's left>\n\n## Notes\n- <anything the next session should know>\n"
\`\`\`

## Interpreting \$ARGUMENTS

| User says | Action |
|-----------|--------|
| \`todo <task>\` | Add a new todo item to Todos.md |
| \`done\` | Show completed tasks, or mark matching task done |
| \`status\` | Show incomplete todos and recent changelog entries |
| \`todos\` | List all incomplete todos |
| \`bootstrap\` | Create the project folder structure in the vault |
| \`handoff\` | Write the Last Session summary |

## Important Notes

- Never delete or overwrite existing content -- only append or toggle tasks.
- Always read before writing when checking for duplicate date headings.
- Keep changelog entries concise -- one line per change.
- Use \`\n\` for newlines in content parameters.
SKILLEOF

# --- Run shared setup ---

configure_knap

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
