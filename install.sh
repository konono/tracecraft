#!/bin/sh
# tracecraft installer — POSIX sh, idempotent, preserves existing hooks.
# Usage:
#   sh install.sh                  # interactive scope selection
#   sh install.sh --global         # install to ~/.claude/ (all projects)
#   sh install.sh --project        # install to current project's .claude/
#   sh install.sh --project --target /path/to/project
set -eu

# ── Configuration ──────────────────────────────────────────────
HOOK_FILE="tracecraft-autostart.sh"
HOOK_TIMEOUT=3000
SKILL_FILE="tracecraft.md"

# ── Resolve source paths ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_HOOK="${SCRIPT_DIR}/hooks/${HOOK_FILE}"
SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_FILE}"

# ── Helpers ────────────────────────────────────────────────────
info() { printf '[tracecraft]  %s\n' "$1"; }
skip() { printf '[tracecraft]  %s (skipped)\n' "$1"; }
err()  { printf '[tracecraft]  %s\n' "$1" >&2; exit 1; }

find_python() {
    for cmd in python3 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            if "$cmd" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' 2>/dev/null; then
                printf '%s' "$cmd"
                return 0
            fi
        fi
    done
    return 1
}

# ── Argument parsing ──────────────────────────────────────────
SCOPE=""
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --global)  SCOPE="global";  shift ;;
        --project) SCOPE="project"; shift ;;
        --target)
            [ $# -ge 2 ] || err "--target requires a path argument"
            TARGET="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: sh install.sh [--global | --project [--target <path>]]\n'
            exit 0 ;;
        *) err "Unknown option: $1" ;;
    esac
done

# ── Interactive scope selection ────────────────────────────────
if [ -z "$SCOPE" ]; then
    printf '\nWhere should tracecraft be installed?\n\n'
    printf '  1) global  — ~/.claude/ (all projects)\n'
    printf '  2) project — current project only\n\n'
    printf 'Select [1/2]: '
    read -r choice
    case "$choice" in
        1|global)  SCOPE="global" ;;
        2|project) SCOPE="project" ;;
        *) err "Invalid selection: $choice" ;;
    esac
fi

# ── Determine destination paths ───────────────────────────────
if [ "$SCOPE" = "global" ]; then
    DEST_BASE="${HOME}/.claude"
    HOOK_CMD="sh ~/.claude/hooks/${HOOK_FILE}"
else
    if [ -n "$TARGET" ]; then
        DEST_BASE="${TARGET}/.claude"
    else
        DEST_BASE=".claude"
    fi
    # Resolve to absolute for display
    DEST_BASE_ABS="$(cd "$(dirname "${DEST_BASE}")" 2>/dev/null && pwd)/$(basename "${DEST_BASE}")" || DEST_BASE_ABS="$DEST_BASE"
    HOOK_CMD="sh .claude/hooks/${HOOK_FILE}"
fi

DEST_HOOKS="${DEST_BASE}/hooks"
DEST_SETTINGS="${DEST_BASE}/settings.json"

# ── Prerequisite checks ──────────────────────────────────────
[ -f "$SOURCE_HOOK" ] || err "Hook source not found: ${SOURCE_HOOK}"
PYTHON="$(find_python)" || err "Python 3.6+ is required but not found. Install python3 and retry."

printf '\n'
info "Scope: ${SCOPE}"
info "Destination: ${DEST_BASE}"
printf '\n'

# ── 1. Install hook script ────────────────────────────────────
mkdir -p "$DEST_HOOKS"

if [ -f "${DEST_HOOKS}/${HOOK_FILE}" ] && cmp -s "$SOURCE_HOOK" "${DEST_HOOKS}/${HOOK_FILE}"; then
    skip "Hook script already up to date"
else
    cp "$SOURCE_HOOK" "${DEST_HOOKS}/${HOOK_FILE}"
    chmod +x "${DEST_HOOKS}/${HOOK_FILE}"
    info "Installed hook script -> ${DEST_HOOKS}/${HOOK_FILE}"
fi

# ── 2. Install skill definition (project scope only) ──────────
if [ "$SCOPE" = "project" ]; then
    DEST_SKILLS="${DEST_BASE}/skills"
    mkdir -p "$DEST_SKILLS"
    if [ -f "${DEST_SKILLS}/${SKILL_FILE}" ] && cmp -s "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"; then
        skip "Skill definition already up to date"
    else
        cp "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"
        info "Installed skill definition -> ${DEST_SKILLS}/${SKILL_FILE}"
    fi
fi

# ── 3. Update settings.json ──────────────────────────────────
"$PYTHON" - "$DEST_SETTINGS" "$HOOK_CMD" "$HOOK_TIMEOUT" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
hook_command  = sys.argv[2]
hook_timeout  = int(sys.argv[3])

hook_entry = {"command": hook_command, "timeout": hook_timeout, "type": "command"}

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])

for matcher in ups:
    for h in matcher.get("hooks", []):
        if h.get("command") == hook_command:
            print("[tracecraft]  Hook entry already in settings.json (skipped)")
            sys.exit(0)

if ups:
    ups[0].setdefault("hooks", []).append(hook_entry)
else:
    ups.append({"hooks": [hook_entry]})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("[tracecraft]  Added hook entry to settings.json")
PYEOF

printf '\n'
info "Installation complete."
