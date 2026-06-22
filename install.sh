#!/bin/sh
# tracecraft installer — POSIX sh, idempotent, preserves existing hooks.
# Usage:
#   sh install.sh                  # interactive (scope selection)
#   sh install.sh --global         # install to ~/.claude/ (all projects)
#   sh install.sh --project        # install to current project's .claude/
#   sh install.sh --project --target /path/to/project
set -eu

# ── Configuration ──────────────────────────────────────────────
AUTOSTART_HOOK="tracecraft-autostart.sh"
PRECOMPACT_HOOK="tracecraft-precompact.sh"
HOOK_TIMEOUT=3000
SKILL_DIR="tracecraft"
SKILL_FILE="SKILL.md"
CLI_NAME="tracecraft"
OC_SKILL_FILE="SKILL.md"
OC_COMMAND_FILE="tracecraft.md"

# ── Resolve source paths ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_AUTOSTART="${SCRIPT_DIR}/hooks/${AUTOSTART_HOOK}"
SOURCE_PRECOMPACT="${SCRIPT_DIR}/hooks/${PRECOMPACT_HOOK}"
SOURCE_SKILL="${SCRIPT_DIR}/.claude/skills/${SKILL_DIR}/${SKILL_FILE}"
SOURCE_CLI="${SCRIPT_DIR}/bin/${CLI_NAME}"
SOURCE_OC_SKILL="${SCRIPT_DIR}/.opencode/skills/${SKILL_DIR}/${OC_SKILL_FILE}"
SOURCE_OC_COMMAND="${SCRIPT_DIR}/.opencode/commands/${OC_COMMAND_FILE}"

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
PLATFORM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --global)  SCOPE="global";  shift ;;
        --project) SCOPE="project"; shift ;;
        --opencode) PLATFORM="opencode"; shift ;;
        --target)
            [ $# -ge 2 ] || err "--target requires a path argument"
            TARGET="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: sh install.sh [--global | --project [--target <path>]] [--opencode]\n'
            printf '\n  --opencode   Install for opencode instead of Claude Code\n'
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
if [ "$PLATFORM" = "opencode" ]; then
    # opencode installation
    if [ "$SCOPE" = "global" ]; then
        OC_BASE="${HOME}/.config/opencode"
    else
        if [ -n "$TARGET" ]; then
            OC_BASE="${TARGET}/.opencode"
        else
            OC_BASE=".opencode"
        fi
    fi

    [ -f "$SOURCE_OC_SKILL" ] || err "OpenCode skill source not found: ${SOURCE_OC_SKILL}"
    [ -f "$SOURCE_OC_COMMAND" ] || err "OpenCode command source not found: ${SOURCE_OC_COMMAND}"
    [ -f "$SOURCE_CLI" ] || err "CLI source not found: ${SOURCE_CLI}"

    printf '\n'
    info "Platform: opencode"
    info "Scope: ${SCOPE}"
    info "Destination: ${OC_BASE}"
    printf '\n'

    # ── Install opencode skill ──────────────────────────────
    OC_SKILL_DIR="${OC_BASE}/skills/${SKILL_DIR}"
    mkdir -p "$OC_SKILL_DIR"
    if [ -f "${OC_SKILL_DIR}/${OC_SKILL_FILE}" ] && cmp -s "$SOURCE_OC_SKILL" "${OC_SKILL_DIR}/${OC_SKILL_FILE}"; then
        skip "Skill definition already up to date"
    else
        cp "$SOURCE_OC_SKILL" "${OC_SKILL_DIR}/${OC_SKILL_FILE}"
        info "Installed skill definition -> ${OC_SKILL_DIR}/${OC_SKILL_FILE}"
    fi

    # ── Install opencode command ────────────────────────────
    OC_CMD_DIR="${OC_BASE}/commands"
    mkdir -p "$OC_CMD_DIR"
    if [ -f "${OC_CMD_DIR}/${OC_COMMAND_FILE}" ] && cmp -s "$SOURCE_OC_COMMAND" "${OC_CMD_DIR}/${OC_COMMAND_FILE}"; then
        skip "Command already up to date"
    else
        cp "$SOURCE_OC_COMMAND" "${OC_CMD_DIR}/${OC_COMMAND_FILE}"
        info "Installed command -> ${OC_CMD_DIR}/${OC_COMMAND_FILE}"
    fi

    # ── Install CLI ─────────────────────────────────────────
    DEST_BIN="${HOME}/.local/bin"
    mkdir -p "$DEST_BIN"
    if [ -f "${DEST_BIN}/${CLI_NAME}" ] && cmp -s "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"; then
        skip "CLI already up to date"
    else
        cp "$SOURCE_CLI" "${DEST_BIN}/${CLI_NAME}"
        chmod +x "${DEST_BIN}/${CLI_NAME}"
        info "Installed CLI -> ${DEST_BIN}/${CLI_NAME}"
    fi

    printf '\n'
    info "Installation complete (opencode)."
    exit 0
fi

# ── Claude Code installation (default) ───────────────────────
if [ "$SCOPE" = "global" ]; then
    DEST_BASE="${HOME}/.claude"
    AUTOSTART_CMD="sh ~/.claude/hooks/${AUTOSTART_HOOK}"
    PRECOMPACT_CMD="sh ~/.claude/hooks/${PRECOMPACT_HOOK}"
else
    if [ -n "$TARGET" ]; then
        DEST_BASE="${TARGET}/.claude"
    else
        DEST_BASE=".claude"
    fi
    AUTOSTART_CMD="sh .claude/hooks/${AUTOSTART_HOOK}"
    PRECOMPACT_CMD="sh .claude/hooks/${PRECOMPACT_HOOK}"
fi

DEST_HOOKS="${DEST_BASE}/hooks"
DEST_SETTINGS="${DEST_BASE}/settings.json"

# ── Prerequisite checks ──────────────────────────────────────
[ -f "$SOURCE_AUTOSTART" ] || err "Autostart hook source not found: ${SOURCE_AUTOSTART}"
[ -f "$SOURCE_PRECOMPACT" ] || err "PreCompact hook source not found: ${SOURCE_PRECOMPACT}"
[ -f "$SOURCE_SKILL" ] || err "Skill source not found: ${SOURCE_SKILL}"
[ -f "$SOURCE_CLI" ] || err "CLI source not found: ${SOURCE_CLI}"
PYTHON="$(find_python)" || err "Python 3.6+ is required but not found. Install python3 and retry."

printf '\n'
info "Platform: Claude Code"
info "Scope: ${SCOPE}"
info "Destination: ${DEST_BASE}"
printf '\n'

# ── 1. Install hook scripts ──────────────────────────────────
mkdir -p "$DEST_HOOKS"

install_hook() {
    _src="$1"; _dst="$2"; _label="$3"
    cp "$_src" "$_dst"
    chmod +x "$_dst"
    info "Installed ${_label} hook -> ${_dst}"
}

install_hook "$SOURCE_AUTOSTART" "${DEST_HOOKS}/${AUTOSTART_HOOK}" "Autostart"
install_hook "$SOURCE_PRECOMPACT" "${DEST_HOOKS}/${PRECOMPACT_HOOK}" "PreCompact"

# ── 2. Remove legacy Stop hook ──────────────────────────────
LEGACY_STOP="${DEST_HOOKS}/tracecraft-stop.sh"
if [ -f "$LEGACY_STOP" ]; then
    rm "$LEGACY_STOP"
    info "Removed legacy Stop hook -> ${LEGACY_STOP}"
fi

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
"$PYTHON" - "$DEST_SETTINGS" "$AUTOSTART_CMD" "$PRECOMPACT_CMD" "$HOOK_TIMEOUT" <<'PYEOF'
import json, os, sys

settings_path   = sys.argv[1]
autostart_cmd   = sys.argv[2]
precompact_cmd  = sys.argv[3]
hook_timeout    = int(sys.argv[4])

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

# Remove legacy Stop hook entries
if "Stop" in hooks:
    for matcher in hooks["Stop"]:
        original = matcher.get("hooks", [])
        matcher["hooks"] = [h for h in original if "tracecraft" not in h.get("command", "")]
    hooks["Stop"] = [m for m in hooks["Stop"] if m.get("hooks")]
    if not hooks["Stop"]:
        del hooks["Stop"]
        print("[tracecraft]  Removed legacy Stop hook from settings.json")

hook_configs = [
    ("UserPromptSubmit", autostart_cmd, hook_timeout),
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
