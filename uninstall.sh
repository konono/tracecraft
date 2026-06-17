#!/bin/sh
# tracecraft uninstaller — POSIX sh, idempotent, preserves other hooks.
# Usage:
#   sh uninstall.sh                  # interactive scope selection
#   sh uninstall.sh --global         # remove from ~/.claude/
#   sh uninstall.sh --project        # remove from current project's .claude/
#   sh uninstall.sh --project --target /path/to/project
set -eu

# ── Configuration ──────────────────────────────────────────────
AUTOSTART_HOOK="tracecraft-autostart.sh"
STOP_HOOK="tracecraft-stop.sh"
SKILL_FILE="tracecraft.md"

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
            printf 'Usage: sh uninstall.sh [--global | --project [--target <path>]]\n'
            exit 0 ;;
        *) err "Unknown option: $1" ;;
    esac
done

# ── Interactive scope selection ────────────────────────────────
if [ -z "$SCOPE" ]; then
    printf '\nWhich installation should be removed?\n\n'
    printf '  1) global  — ~/.claude/\n'
    printf '  2) project — current project\n\n'
    printf 'Select [1/2]: '
    read -r choice
    case "$choice" in
        1|global)  SCOPE="global" ;;
        2|project) SCOPE="project" ;;
        *) err "Invalid selection: $choice" ;;
    esac
fi

# ── Determine paths ──────────────────────────────────────────
if [ "$SCOPE" = "global" ]; then
    DEST_BASE="${HOME}/.claude"
else
    if [ -n "$TARGET" ]; then
        DEST_BASE="${TARGET}/.claude"
    else
        DEST_BASE=".claude"
    fi
fi

DEST_HOOKS="${DEST_BASE}/hooks"
DEST_SETTINGS="${DEST_BASE}/settings.json"

printf '\n'
info "Scope: ${SCOPE}"
info "Target: ${DEST_BASE}"
printf '\n'

# ── 1. Remove hook entries from settings.json ────────────────
if [ -f "$DEST_SETTINGS" ]; then
    PYTHON="$(find_python)" || err "Python 3.6+ is required but not found."

    "$PYTHON" - "$DEST_SETTINGS" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]

autostart_commands = {
    "sh ~/.claude/hooks/tracecraft-autostart.sh",
    "bash ~/.claude/hooks/tracecraft-autostart.sh",
    "sh .claude/hooks/tracecraft-autostart.sh",
    "bash .claude/hooks/tracecraft-autostart.sh",
}

stop_commands = {
    "sh ~/.claude/hooks/tracecraft-stop.sh",
    "bash ~/.claude/hooks/tracecraft-stop.sh",
    "sh .claude/hooks/tracecraft-stop.sh",
    "bash .claude/hooks/tracecraft-stop.sh",
}

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})

removed_autostart = False
for matcher in hooks.get("UserPromptSubmit", []):
    original = matcher.get("hooks", [])
    filtered = [h for h in original if h.get("command") not in autostart_commands]
    if len(filtered) < len(original):
        removed_autostart = True
        matcher["hooks"] = filtered

removed_stop = False
for matcher in hooks.get("Stop", []):
    original = matcher.get("hooks", [])
    filtered = [h for h in original if h.get("command") not in stop_commands]
    if len(filtered) < len(original):
        removed_stop = True
        matcher["hooks"] = filtered

for event in ["UserPromptSubmit", "Stop"]:
    if event in hooks:
        hooks[event] = [m for m in hooks[event] if m.get("hooks")]
        if not hooks[event]:
            del hooks[event]
if not hooks:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

if removed_autostart:
    print("[tracecraft]  Removed autostart hook from settings.json")
else:
    print("[tracecraft]  No autostart hook found in settings.json (skipped)")

if removed_stop:
    print("[tracecraft]  Removed stop hook from settings.json")
else:
    print("[tracecraft]  No stop hook found in settings.json (skipped)")
PYEOF
else
    skip "No settings.json found at ${DEST_SETTINGS}"
fi

# ── 2. Remove hook scripts ──────────────────────────────────
for hook in "$AUTOSTART_HOOK" "$STOP_HOOK"; do
    if [ -f "${DEST_HOOKS}/${hook}" ]; then
        rm "${DEST_HOOKS}/${hook}"
        info "Removed hook script: ${DEST_HOOKS}/${hook}"
    else
        skip "Hook script not found at ${DEST_HOOKS}/${hook}"
    fi
done

# ── 3. Remove skill definition (project scope only) ──────────
if [ "$SCOPE" = "project" ]; then
    DEST_SKILL="${DEST_BASE}/skills/${SKILL_FILE}"
    if [ -f "$DEST_SKILL" ]; then
        rm "$DEST_SKILL"
        info "Removed skill definition: ${DEST_SKILL}"
    else
        skip "Skill definition not found at ${DEST_SKILL}"
    fi
fi

# ── 4. Clean up temp files ───────────────────────────────────
if [ -d "/tmp/tracecraft-checkpoint" ]; then
    rm -rf "/tmp/tracecraft-checkpoint"
    info "Cleaned up temp files: /tmp/tracecraft-checkpoint"
fi
if [ -d "/tmp/tracecraft-stop" ]; then
    rm -rf "/tmp/tracecraft-stop"
    info "Cleaned up temp files: /tmp/tracecraft-stop"
fi

printf '\n'
info "Uninstallation complete."
