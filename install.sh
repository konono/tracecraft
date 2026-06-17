#!/bin/sh
# tracecraft installer — POSIX sh, idempotent, preserves existing hooks.
# Usage:
#   sh install.sh                  # interactive (scope + variant)
#   sh install.sh --global         # install to ~/.claude/ (all projects)
#   sh install.sh --project        # install to current project's .claude/
#   sh install.sh --project --target /path/to/project
#   sh install.sh --variant test   # with deferred auto-checkpoint (default)
#   sh install.sh --variant main   # without auto-checkpoint (original behavior)
set -eu

# ── Configuration ──────────────────────────────────────────────
AUTOSTART_HOOK="tracecraft-autostart.sh"
STOP_HOOK="tracecraft-stop.sh"
HOOK_TIMEOUT=3000
SKILL_DIR="tracecraft"
SKILL_FILE="SKILL.md"
CLI_NAME="tracecraft"

# ── Resolve source paths ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_AUTOSTART="${SCRIPT_DIR}/hooks/${AUTOSTART_HOOK}"
SOURCE_STOP="${SCRIPT_DIR}/hooks/${STOP_HOOK}"
SOURCE_CLI="${SCRIPT_DIR}/bin/${CLI_NAME}"

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
VARIANT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --global)  SCOPE="global";  shift ;;
        --project) SCOPE="project"; shift ;;
        --target)
            [ $# -ge 2 ] || err "--target requires a path argument"
            TARGET="$2"; shift 2 ;;
        --variant)
            [ $# -ge 2 ] || err "--variant requires 'main' or 'test'"
            VARIANT="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: sh install.sh [--global | --project [--target <path>]] [--variant main|test]\n\n'
            printf 'Variants:\n'
            printf '  main  — Original behavior (UserPromptSubmit autostart only)\n'
            printf '  test  — Deferred auto-checkpoint via Stop + UserPromptSubmit hooks\n'
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

# ── Interactive variant selection ──────────────────────────────
if [ -z "$VARIANT" ]; then
    printf '\nWhich variant?\n\n'
    printf '  1) test — Auto-checkpoint + auto-finalize (recommended)\n'
    printf '  2) main — Original behavior (manual finalize)\n\n'
    printf 'Select [1/2]: '
    read -r vchoice
    case "$vchoice" in
        1|test)  VARIANT="test" ;;
        2|main)  VARIANT="main" ;;
        *) err "Invalid selection: $vchoice" ;;
    esac
fi

case "$VARIANT" in
    main|test) ;;
    *) err "Invalid variant: $VARIANT (must be 'main' or 'test')" ;;
esac

# ── Resolve skill source based on variant ─────────────────────
if [ "$VARIANT" = "main" ]; then
    SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_DIR}/SKILL.main.md"
    [ -f "$SOURCE_SKILL" ] || SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_DIR}/${SKILL_FILE}"
else
    SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_DIR}/${SKILL_FILE}"
fi

# ── Determine destination paths ───────────────────────────────
if [ "$SCOPE" = "global" ]; then
    DEST_BASE="${HOME}/.claude"
    AUTOSTART_CMD="sh ~/.claude/hooks/${AUTOSTART_HOOK}"
    STOP_CMD="sh ~/.claude/hooks/${STOP_HOOK}"
else
    if [ -n "$TARGET" ]; then
        DEST_BASE="${TARGET}/.claude"
    else
        DEST_BASE=".claude"
    fi
    AUTOSTART_CMD="sh .claude/hooks/${AUTOSTART_HOOK}"
    STOP_CMD="sh .claude/hooks/${STOP_HOOK}"
fi

DEST_HOOKS="${DEST_BASE}/hooks"
DEST_SETTINGS="${DEST_BASE}/settings.json"

# ── Prerequisite checks ──────────────────────────────────────
[ -f "$SOURCE_AUTOSTART" ] || err "Autostart hook source not found: ${SOURCE_AUTOSTART}"
[ -f "$SOURCE_SKILL" ] || err "Skill source not found: ${SOURCE_SKILL}"
[ -f "$SOURCE_CLI" ] || err "CLI source not found: ${SOURCE_CLI}"
PYTHON="$(find_python)" || err "Python 3.6+ is required but not found. Install python3 and retry."

printf '\n'
info "Scope: ${SCOPE}"
info "Variant: ${VARIANT}"
info "Destination: ${DEST_BASE}"
printf '\n'

# ── 1. Install hook scripts ──────────────────────────────────
mkdir -p "$DEST_HOOKS"

# Autostart hook (both variants — test variant has checkpoint logic integrated)
if [ -f "${DEST_HOOKS}/${AUTOSTART_HOOK}" ] && cmp -s "$SOURCE_AUTOSTART" "${DEST_HOOKS}/${AUTOSTART_HOOK}"; then
    skip "Autostart hook already up to date"
else
    cp "$SOURCE_AUTOSTART" "${DEST_HOOKS}/${AUTOSTART_HOOK}"
    chmod +x "${DEST_HOOKS}/${AUTOSTART_HOOK}"
    info "Installed autostart hook -> ${DEST_HOOKS}/${AUTOSTART_HOOK}"
fi

# Stop hook (test variant only — silent flag-setter)
if [ "$VARIANT" = "test" ]; then
    if [ -f "$SOURCE_STOP" ]; then
        if [ -f "${DEST_HOOKS}/${STOP_HOOK}" ] && cmp -s "$SOURCE_STOP" "${DEST_HOOKS}/${STOP_HOOK}"; then
            skip "Stop hook already up to date"
        else
            cp "$SOURCE_STOP" "${DEST_HOOKS}/${STOP_HOOK}"
            chmod +x "${DEST_HOOKS}/${STOP_HOOK}"
            info "Installed stop hook -> ${DEST_HOOKS}/${STOP_HOOK}"
        fi
    fi
else
    if [ -f "${DEST_HOOKS}/${STOP_HOOK}" ]; then
        rm "${DEST_HOOKS}/${STOP_HOOK}"
        info "Removed stop hook (main variant) -> ${DEST_HOOKS}/${STOP_HOOK}"
    fi
fi

# ── 2. Clean up legacy paths ─────────────────────────────────
for legacy in \
    "${DEST_BASE}/commands/${SKILL_DIR}.md" \
    "${DEST_BASE}/skills/${SKILL_DIR}.md"; do
    if [ -f "$legacy" ]; then
        rm "$legacy"
        info "Removed legacy skill file -> ${legacy}"
    fi
done

# ── 3. Install skill definition ───────────────────────────────
DEST_SKILLS="${DEST_BASE}/skills/${SKILL_DIR}"
mkdir -p "$DEST_SKILLS"
if [ -f "${DEST_SKILLS}/${SKILL_FILE}" ] && cmp -s "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"; then
    skip "Skill definition already up to date"
else
    cp "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"
    info "Installed skill definition (${VARIANT}) -> ${DEST_SKILLS}/${SKILL_FILE}"
fi

# ── 4. Install CLI ───────────────────────────────────────────
DEST_BIN="${HOME}/.local/bin"
mkdir -p "$DEST_BIN"
if [ -f "${DEST_BIN}/${CLI_NAME}" ] && cmp -s "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"; then
    skip "CLI already up to date"
else
    cp "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"
    chmod +x "${DEST_BIN}/${CLI_NAME}"
    info "Installed CLI -> ${DEST_BIN}/${CLI_NAME}"
fi

# ── 5. Update settings.json ──────────────────────────────────
"$PYTHON" - "$DEST_SETTINGS" "$AUTOSTART_CMD" "$STOP_CMD" "$HOOK_TIMEOUT" "$VARIANT" <<'PYEOF'
import json, os, sys

settings_path   = sys.argv[1]
autostart_cmd   = sys.argv[2]
stop_cmd        = sys.argv[3]
hook_timeout    = int(sys.argv[4])
variant         = sys.argv[5]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

# --- UserPromptSubmit: autostart hook (both variants) ---
ups = hooks.setdefault("UserPromptSubmit", [])
autostart_exists = False
for matcher in ups:
    for h in matcher.get("hooks", []):
        if h.get("command") == autostart_cmd:
            autostart_exists = True
            break

if not autostart_exists:
    entry = {"command": autostart_cmd, "timeout": hook_timeout, "type": "command"}
    if ups:
        ups[0].setdefault("hooks", []).append(entry)
    else:
        ups.append({"hooks": [entry]})
    print("[tracecraft]  Added autostart hook to settings.json")
else:
    print("[tracecraft]  Autostart hook already in settings.json (skipped)")

# --- Stop: silent flag-setter (test variant only) ---
stop_commands = {stop_cmd, stop_cmd.replace("sh ", "bash ", 1)}

if variant == "test":
    stop_hooks = hooks.get("Stop", [])
    stop_exists = False
    for matcher in stop_hooks:
        for h in matcher.get("hooks", []):
            if h.get("command") in stop_commands:
                stop_exists = True
                break

    if not stop_exists:
        entry = {"command": stop_cmd, "timeout": 3000, "type": "command"}
        if hooks.get("Stop"):
            hooks["Stop"][0].setdefault("hooks", []).append(entry)
        else:
            hooks["Stop"] = [{"hooks": [entry]}]
        print("[tracecraft]  Added stop hook to settings.json")
    else:
        print("[tracecraft]  Stop hook already in settings.json (skipped)")
else:
    # main variant: remove stop hook entries
    removed = False
    for matcher in hooks.get("Stop", []):
        original = matcher.get("hooks", [])
        filtered = [h for h in original if h.get("command") not in stop_commands]
        if len(filtered) < len(original):
            removed = True
            matcher["hooks"] = filtered

    if removed:
        hooks["Stop"] = [m for m in hooks.get("Stop", []) if m.get("hooks")]
        if not hooks["Stop"]:
            del hooks["Stop"]
        print("[tracecraft]  Removed stop hook from settings.json")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

PYEOF

printf '\n'
info "Installation complete (variant: ${VARIANT})."
if [ "$VARIANT" = "test" ]; then
    info "Deferred auto-checkpoint: journals updated at the start of each turn."
    info "Switch back with: sh install.sh --variant main"
else
    info "Original behavior: manual /tracecraft finalize required."
    info "Try the test variant: sh install.sh --variant test"
fi
