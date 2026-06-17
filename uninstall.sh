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
PRECOMPACT_HOOK="tracecraft-precompact.sh"
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

tracecraft_commands = set()
for hook_name in ["tracecraft-autostart.sh", "tracecraft-stop.sh", "tracecraft-precompact.sh"]:
    for prefix in ["sh ~/.claude/hooks/", "bash ~/.claude/hooks/",
                    "sh .claude/hooks/", "bash .claude/hooks/"]:
        tracecraft_commands.add(prefix + hook_name)

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})

for event in ["UserPromptSubmit", "Stop", "PreCompact"]:
    removed = False
    for matcher in hooks.get(event, []):
        original = matcher.get("hooks", [])
        filtered = [h for h in original if h.get("command") not in tracecraft_commands]
        if len(filtered) < len(original):
            removed = True
            matcher["hooks"] = filtered
    if removed:
        hooks[event] = [m for m in hooks.get(event, []) if m.get("hooks")]
        if not hooks[event]:
            del hooks[event]
        print(f"[tracecraft]  Removed {event} hook from settings.json")
    else:
        print(f"[tracecraft]  No {event} hook found in settings.json (skipped)")

if not hooks:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

PYEOF
else
    skip "No settings.json found at ${DEST_SETTINGS}"
fi

# ── 2. Remove hook scripts ──────────────────────────────────
for hook in "$AUTOSTART_HOOK" "$STOP_HOOK" "$PRECOMPACT_HOOK"; do
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
    fi
fi

# ── 4. Clean up temp files ───────────────────────────────────
for tmpdir in \
    "/tmp/tracecraft-checkpoint" \
    "/tmp/tracecraft-checkpoint-lock" \
    "/tmp/tracecraft-checkpoint-done" \
    "/tmp/tracecraft-interval" \
    "/tmp/tracecraft-stop"; do
    if [ -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
        info "Cleaned up: ${tmpdir}"
    fi
done

printf '\n'
info "Uninstallation complete."
