#!/bin/sh
# tracecraft autostart hook for UserPromptSubmit
# 2つの役割:
#   1. ジャーナル未開始なら start を促す（従来機能）
#   2. checkpoint フラグがあれば deferred checkpoint を指示する（重複防止付き）
[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

INPUT=$(cat)

[ -f ".claude/skills/tracecraft/SKILL.md" ] || [ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

# Settings (rendered by install.sh)
TRACECRAFT_MODEL=__TRACECRAFT_MODEL__
TRACECRAFT_TIMING=__TRACECRAFT_TIMING__
TRACECRAFT_LOCK_TIMEOUT=__TRACECRAFT_LOCK_TIMEOUT__

# session_id を取得（先頭8文字を短縮IDとして使用）
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

# --- 役割1: ジャーナル未開始なら start を促す ---
if ! ls .tracecraft/*_${SESSION_ID}*/worklog.md >/dev/null 2>&1; then
    cat <<MSG
tracecraft: ジャーナル未開始。ユーザーのメッセージに応答する前に、まず Skill ツールで tracecraft start を実行してセッション ${SESSION_ID} のジャーナルを開始してください。ジャーナル初期化後は必ずユーザーの元のメッセージ（プロンプト）の処理を続行すること。ジャーナル作成だけで応答を終えてはならない。セッションID: ${SESSION_ID}
MSG
    exit 0
fi

# --- 役割2: checkpoint フラグがあれば deferred checkpoint を指示する ---
# timing=off の場合はチェックポイント処理をスキップ
[ "$TRACECRAFT_TIMING" = "off" ] && exit 0

FLAG_FILE="/tmp/tracecraft-checkpoint/${SESSION_ID}"
if [ -f "$FLAG_FILE" ]; then
    SESSION_DIR=$(cat "$FLAG_FILE" 2>/dev/null)

    # --- ハイブリッドロック: 完了マーカー + タイムアウト ---
    LOCK_DIR="/tmp/tracecraft-checkpoint-lock"
    DONE_DIR="/tmp/tracecraft-checkpoint-done"
    mkdir -p "$LOCK_DIR" "$DONE_DIR" 2>/dev/null
    LOCK="$LOCK_DIR/${SESSION_ID}"
    DONE="$DONE_DIR/${SESSION_ID}"

    # Agent完了マーカーがあればロック解除
    [ -f "$DONE" ] && rm -f "$LOCK" "$DONE"

    if [ -f "$LOCK" ]; then
        AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
        if [ "$AGE" -lt "$TRACECRAFT_LOCK_TIMEOUT" ]; then
            rm -f "$FLAG_FILE"
            exit 0
        fi
        rm -f "$LOCK"
    fi

    rm -f "$FLAG_FILE"

    if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ]; then
        touch "$LOCK"
        rm -f "$DONE"
        cat <<MSG
tracecraft checkpoint: Agent(model="${TRACECRAFT_MODEL}", run_in_background=true) を起動し、セッションディレクトリ ${SESSION_DIR} のジャーナルを更新させよ。Agent が記録要否を判断する。完了後 touch ${DONE} を実行させること。直接 Write/Edit せず必ず Agent に委譲すること。
MSG
    fi
fi
