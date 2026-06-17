#!/bin/sh
# tracecraft autostart hook for UserPromptSubmit
# 2つの役割:
#   1. ジャーナル未開始なら start を促す（従来機能）
#   2. checkpoint フラグがあれば deferred checkpoint を指示する（重複防止付き）
[ "$TRACECRAFT" = "0" ] && exit 0
[ -f "$HOME/.tracecraft-disabled" ] && [ "$TRACECRAFT" != "1" ] && exit 0

INPUT=$(cat)

[ -f ".claude/skills/tracecraft/SKILL.md" ] || [ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

# Load config
TRACECRAFT_MODEL=haiku
TRACECRAFT_TIMING=every
TRACECRAFT_LOCK_TIMEOUT=90
[ -f "$HOME/.tracecraft-config" ] && . "$HOME/.tracecraft-config"

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
tracecraft checkpoint: 前ターンの作業内容を記録してください。以下の手順で行うこと:

1. 直前のターン（このメッセージの直前のユーザーへの応答）で行った作業・調査・判断を簡潔にサマリする
2. Agent ツールを run_in_background=true, model="${TRACECRAFT_MODEL}" で起動し、以下を指示する:
   - セッションディレクトリ: ${SESSION_DIR}
   - サマリの内容を worklog.md に新しい Step として追記する
   - 調査結果があれば findings.md に、判断があれば decisions.md に、問題があれば troubleshooting.md に追記する
   - finalize（final-guide.md / retrospective.md の再生成）は不要。ソースファイルへの追記のみ行うこと
   - 完了後、以下のコマンドを Bash ツールで実行すること: touch ${DONE}
3. Agent 起動後、すぐにユーザーの現在のメッセージの処理に進むこと。Agent の完了を待たないこと。

重要: 直接 Write/Edit でジャーナルファイルを書かないこと。必ず Agent に委譲すること。
重要: Agent は model="${TRACECRAFT_MODEL}" で起動すること。
MSG
    fi
fi
