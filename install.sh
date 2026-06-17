#!/bin/sh
# tracecraft installer — POSIX sh, idempotent, preserves existing hooks.
# Usage:
#   sh install.sh                  # interactive (scope + timing + model)
#   sh install.sh --global         # install to ~/.claude/ (all projects)
#   sh install.sh --project        # install to current project's .claude/
#   sh install.sh --project --target /path/to/project
#   sh install.sh --timing every   # checkpoint timing (off|every|precompact|interval:N)
#   sh install.sh --model haiku    # checkpoint agent model (haiku|sonnet|opus)
#   sh install.sh --lock-timeout 90  # lock timeout in seconds
set -eu

# ── Configuration ──────────────────────────────────────────────
AUTOSTART_HOOK="tracecraft-autostart.sh"
STOP_HOOK="tracecraft-stop.sh"
PRECOMPACT_HOOK="tracecraft-precompact.sh"
HOOK_TIMEOUT=3000
SKILL_DIR="tracecraft"
SKILL_FILE="SKILL.md"
CLI_NAME="tracecraft"
CONFIG_FILE="$HOME/.tracecraft-config"

# ── Resolve source paths ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_AUTOSTART="${SCRIPT_DIR}/hooks/${AUTOSTART_HOOK}"
SOURCE_STOP="${SCRIPT_DIR}/hooks/${STOP_HOOK}"
SOURCE_PRECOMPACT="${SCRIPT_DIR}/hooks/${PRECOMPACT_HOOK}"
SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_DIR}/${SKILL_FILE}"
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

# ── Load existing config defaults ─────────────────────────────
EXISTING_MODEL=""
EXISTING_TIMING=""
EXISTING_LOCK_TIMEOUT=""
if [ -f "$CONFIG_FILE" ]; then
    EXISTING_MODEL=$(grep '^TRACECRAFT_MODEL=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || true)
    EXISTING_TIMING=$(grep '^TRACECRAFT_TIMING=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || true)
    EXISTING_LOCK_TIMEOUT=$(grep '^TRACECRAFT_LOCK_TIMEOUT=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || true)
fi

# ── Argument parsing ──────────────────────────────────────────
SCOPE=""
TARGET=""
OPT_TIMING=""
OPT_MODEL=""
OPT_LOCK_TIMEOUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --global)  SCOPE="global";  shift ;;
        --project) SCOPE="project"; shift ;;
        --target)
            [ $# -ge 2 ] || err "--target requires a path argument"
            TARGET="$2"; shift 2 ;;
        --timing)
            [ $# -ge 2 ] || err "--timing requires a value (off|every|precompact|interval:N)"
            OPT_TIMING="$2"; shift 2 ;;
        --model)
            [ $# -ge 2 ] || err "--model requires a value (haiku|sonnet|opus)"
            OPT_MODEL="$2"; shift 2 ;;
        --lock-timeout)
            [ $# -ge 2 ] || err "--lock-timeout requires a number"
            OPT_LOCK_TIMEOUT="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: sh install.sh [--global | --project [--target <path>]] [--timing T] [--model M] [--lock-timeout N]\n\n'
            printf 'Timing modes:\n'
            printf '  off         — No auto-checkpoint (manual /tracecraft finalize only)\n'
            printf '  every       — Checkpoint every turn (default)\n'
            printf '  precompact  — Checkpoint on context compression only\n'
            printf '  interval:N  — Checkpoint every N turns\n\n'
            printf 'Models: haiku (default), sonnet, opus\n'
            exit 0 ;;
        *) err "Unknown option: $1" ;;
    esac
done

# ── Resolve final config values (CLI > existing config > defaults) ──
FINAL_MODEL="${OPT_MODEL:-${EXISTING_MODEL:-haiku}}"
FINAL_TIMING="${OPT_TIMING:-${EXISTING_TIMING:-every}}"
FINAL_LOCK_TIMEOUT="${OPT_LOCK_TIMEOUT:-${EXISTING_LOCK_TIMEOUT:-90}}"

# Validate timing
case "$FINAL_TIMING" in
    off|every|precompact) ;;
    interval:*) ;;
    *) err "Invalid timing: $FINAL_TIMING (must be off|every|precompact|interval:N)" ;;
esac

# Validate model
case "$FINAL_MODEL" in
    haiku|sonnet|opus) ;;
    *) err "Invalid model: $FINAL_MODEL (must be haiku|sonnet|opus)" ;;
esac

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

# ── Interactive timing selection (if not specified) ────────────
if [ -z "$OPT_TIMING" ] && [ -z "$EXISTING_TIMING" ]; then
    printf '\nCheckpoint timing?\n\n'
    printf '  1) every       — Every turn (default)\n'
    printf '  2) precompact  — On context compression only\n'
    printf '  3) interval:5  — Every 5 turns\n'
    printf '  4) off         — Manual only\n\n'
    printf 'Select [1/2/3/4]: '
    read -r tchoice
    case "$tchoice" in
        1|every)      FINAL_TIMING="every" ;;
        2|precompact) FINAL_TIMING="precompact" ;;
        3|interval*)  FINAL_TIMING="interval:5" ;;
        4|off)        FINAL_TIMING="off" ;;
        *) FINAL_TIMING="every" ;;
    esac
fi

# ── Determine destination paths ───────────────────────────────
if [ "$SCOPE" = "global" ]; then
    DEST_BASE="${HOME}/.claude"
    AUTOSTART_CMD="sh ~/.claude/hooks/${AUTOSTART_HOOK}"
    STOP_CMD="sh ~/.claude/hooks/${STOP_HOOK}"
    PRECOMPACT_CMD="sh ~/.claude/hooks/${PRECOMPACT_HOOK}"
else
    if [ -n "$TARGET" ]; then
        DEST_BASE="${TARGET}/.claude"
    else
        DEST_BASE=".claude"
    fi
    AUTOSTART_CMD="sh .claude/hooks/${AUTOSTART_HOOK}"
    STOP_CMD="sh .claude/hooks/${STOP_HOOK}"
    PRECOMPACT_CMD="sh .claude/hooks/${PRECOMPACT_HOOK}"
fi

DEST_HOOKS="${DEST_BASE}/hooks"
DEST_SETTINGS="${DEST_BASE}/settings.json"

# ── Prerequisite checks ──────────────────────────────────────
[ -f "$SOURCE_AUTOSTART" ] || err "Autostart hook source not found: ${SOURCE_AUTOSTART}"
[ -f "$SOURCE_STOP" ] || err "Stop hook source not found: ${SOURCE_STOP}"
[ -f "$SOURCE_PRECOMPACT" ] || err "PreCompact hook source not found: ${SOURCE_PRECOMPACT}"
[ -f "$SOURCE_SKILL" ] || err "Skill source not found: ${SOURCE_SKILL}"
[ -f "$SOURCE_CLI" ] || err "CLI source not found: ${SOURCE_CLI}"
PYTHON="$(find_python)" || err "Python 3.6+ is required but not found. Install python3 and retry."

printf '\n'
info "Scope: ${SCOPE}"
info "Timing: ${FINAL_TIMING}"
info "Model: ${FINAL_MODEL}"
info "Lock timeout: ${FINAL_LOCK_TIMEOUT}s"
info "Destination: ${DEST_BASE}"
printf '\n'

# ── 1. Write config file ────────────────────────────────────
cat > "$CONFIG_FILE" <<CONF
TRACECRAFT_MODEL=${FINAL_MODEL}
TRACECRAFT_TIMING=${FINAL_TIMING}
TRACECRAFT_LOCK_TIMEOUT=${FINAL_LOCK_TIMEOUT}
CONF
info "Config written -> ${CONFIG_FILE}"

# ── 2. Install hook scripts ──────────────────────────────────
mkdir -p "$DEST_HOOKS"

for src_dst in \
    "${SOURCE_AUTOSTART}:${DEST_HOOKS}/${AUTOSTART_HOOK}:Autostart" \
    "${SOURCE_STOP}:${DEST_HOOKS}/${STOP_HOOK}:Stop" \
    "${SOURCE_PRECOMPACT}:${DEST_HOOKS}/${PRECOMPACT_HOOK}:PreCompact"; do
    src=$(echo "$src_dst" | cut -d: -f1)
    dst=$(echo "$src_dst" | cut -d: -f2)
    label=$(echo "$src_dst" | cut -d: -f3)
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        skip "${label} hook already up to date"
    else
        cp "$src" "$dst"
        chmod +x "$dst"
        info "Installed ${label} hook -> ${dst}"
    fi
done

# ── 3. Clean up legacy paths ─────────────────────────────────
for legacy in \
    "${DEST_BASE}/commands/${SKILL_DIR}.md" \
    "${DEST_BASE}/skills/${SKILL_DIR}.md" \
    "${DEST_BASE}/skills/${SKILL_DIR}/SKILL.main.md"; do
    if [ -f "$legacy" ]; then
        rm "$legacy"
        info "Removed legacy file -> ${legacy}"
    fi
done

# ── 4. Install skill definition ───────────────────────────────
DEST_SKILLS="${DEST_BASE}/skills/${SKILL_DIR}"
mkdir -p "$DEST_SKILLS"
if [ -f "${DEST_SKILLS}/${SKILL_FILE}" ] && cmp -s "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"; then
    skip "Skill definition already up to date"
else
    cp "$SOURCE_SKILL" "${DEST_SKILLS}/${SKILL_FILE}"
    info "Installed skill definition -> ${DEST_SKILLS}/${SKILL_FILE}"
fi

# ── 5. Install CLI ───────────────────────────────────────────
DEST_BIN="${HOME}/.local/bin"
mkdir -p "$DEST_BIN"
if [ -f "${DEST_BIN}/${CLI_NAME}" ] && cmp -s "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"; then
    skip "CLI already up to date"
else
    cp "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"
    chmod +x "${DEST_BIN}/${CLI_NAME}"
    info "Installed CLI -> ${DEST_BIN}/${CLI_NAME}"
fi

# ── 6. Update settings.json ──────────────────────────────────
"$PYTHON" - "$DEST_SETTINGS" "$AUTOSTART_CMD" "$STOP_CMD" "$PRECOMPACT_CMD" "$HOOK_TIMEOUT" <<'PYEOF'
import json, os, sys

settings_path   = sys.argv[1]
autostart_cmd   = sys.argv[2]
stop_cmd        = sys.argv[3]
precompact_cmd  = sys.argv[4]
hook_timeout    = int(sys.argv[5])

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

hook_configs = [
    ("UserPromptSubmit", autostart_cmd, hook_timeout),
    ("Stop", stop_cmd, 5000),
    ("PreCompact", precompact_cmd, 5000),
]

for event, cmd, timeout in hook_configs:
    matchers = hooks.setdefault(event, [])
    exists = False
    for matcher in matchers:
        for h in matcher.get("hooks", []):
            if h.get("command") == cmd:
                exists = True
                break

    if not exists:
        entry = {"command": cmd, "timeout": timeout, "type": "command"}
        if matchers:
            matchers[0].setdefault("hooks", []).append(entry)
        else:
            matchers.append({"hooks": [entry]})
        print(f"[tracecraft]  Added {event} hook to settings.json")
    else:
        print(f"[tracecraft]  {event} hook already in settings.json (skipped)")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

PYEOF

printf '\n'
info "Installation complete."
info "Config: ${CONFIG_FILE}"
info "  TRACECRAFT_MODEL=${FINAL_MODEL}"
info "  TRACECRAFT_TIMING=${FINAL_TIMING}"
info "  TRACECRAFT_LOCK_TIMEOUT=${FINAL_LOCK_TIMEOUT}"
printf '\n'
info "Edit ${CONFIG_FILE} to change settings (no reinstall needed)."
