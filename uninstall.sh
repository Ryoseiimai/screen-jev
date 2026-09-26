#!/bin/bash
# uninstall.sh: 画面Jevを止めてフックを外す。記録(~/.screen-jev)はバックアップとして残す。
set -euo pipefail

DATA_DIR="$HOME/.screen-jev"
BIN_DIR="$DATA_DIR/bin"

IS_PROJECT_ONLY=0
TARGET_SETTINGS="$HOME/.claude/settings.json"
if [[ "${1:-}" == "--project" ]]; then
  PROJECT_DIR="${2:?--project にはディレクトリを指定してください}"
  TARGET_SETTINGS="$PROJECT_DIR/.claude/settings.json"
  IS_PROJECT_ONLY=1
fi

# --project 指定時は「このフォルダのフックを外す」だけ。
# 見張り(共有プロセス)や記録データは他プロジェクトでも使われている可能性があるため触らない。
if [[ "$IS_PROJECT_ONLY" -eq 0 ]] && [[ -f "$BIN_DIR/sjev" ]]; then
  if [[ -f "$DATA_DIR/watch.pid" ]]; then
    PID="$(cat "$DATA_DIR/watch.pid" 2>/dev/null || true)"
    if [[ -n "$PID" ]]; then
      kill "$PID" 2>/dev/null || true
    fi
  fi
fi

if [[ -f "$TARGET_SETTINGS" ]]; then
  BACKUP="${TARGET_SETTINGS}.bak-$(date +%Y%m%d%H%M%S)"
  cp "$TARGET_SETTINGS" "$BACKUP"
  echo "==> バックアップ: $BACKUP"

  SESSION_CMD="$BIN_DIR/sjev ensure >/dev/null 2>&1 || true"
  HOOK_CMD="$BIN_DIR/sjev hook"

  python3 - "$TARGET_SETTINGS" "$SESSION_CMD" "$HOOK_CMD" <<'PYEOF'
import json
import sys

path, session_cmd, hook_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

hooks = data.get("hooks", {})


def strip(entries, cmd):
    kept = []
    for group in entries:
        group["hooks"] = [h for h in group.get("hooks", []) if h.get("command") != cmd]
        if group["hooks"]:
            kept.append(group)
    return kept


if "SessionStart" in hooks:
    hooks["SessionStart"] = strip(hooks["SessionStart"], session_cmd)
if "UserPromptSubmit" in hooks:
    hooks["UserPromptSubmit"] = strip(hooks["UserPromptSubmit"], hook_cmd)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PYEOF
  echo "==> フックを外しました"
fi

if [[ "$IS_PROJECT_ONLY" -eq 1 ]]; then
  echo "==> このプロジェクトのフックだけ外しました(共有の見張り・記録データはそのままです)"
else
  echo "==> 記録データは $DATA_DIR に残しています(手動で消す場合は rm -rf \"$DATA_DIR\")"
fi
echo "完了"
