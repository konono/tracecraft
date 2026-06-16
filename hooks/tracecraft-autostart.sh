#!/bin/sh
# tracecraft autostart hook for UserPromptSubmit
# セッションIDベースでジャーナルの初期化状態を判定し、未開始なら Claude に通知する
INPUT=$(cat)

[ -f ".claude/skills/tracecraft/SKILL.md" ] || [ -f "$HOME/.claude/skills/tracecraft/SKILL.md" ] || exit 0

# session_id を取得（先頭8文字を短縮IDとして使用）
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | cut -c1-8)
[ -z "$SESSION_ID" ] && exit 0

# このセッションのジャーナルが既にあればサイレント終了
ls .tracecraft/*_${SESSION_ID}*/worklog.md >/dev/null 2>&1 && exit 0

cat <<MSG
tracecraft: ジャーナル未開始。ユーザーのメッセージに応答する前に、まず Skill ツールで tracecraft start を実行してセッション ${SESSION_ID} のジャーナルを開始してください。これは必須です。セッションID: ${SESSION_ID}
MSG
