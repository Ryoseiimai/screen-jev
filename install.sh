#!/bin/bash
# install.sh: 画面Jevを入れる。
#   ./install.sh              -> ~/.claude/settings.json にフックを追記
#   ./install.sh --project X  -> X/.claude/settings.json にだけ追記(グローバルは触らない)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.screen-jev"
BIN_DIR="$DATA_DIR/bin"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 が見つかりません。標準のmacOSには入っているはずです。Xcodeコマンドラインツールを入れてから、もう一度お試しください: xcode-select --install"
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc が見つかりません。ターミナルで次を実行してから、もう一度お試しください: xcode-select --install"
  exit 1
fi

TARGET_SETTINGS="$HOME/.claude/settings.json"
if [[ "${1:-}" == "--project" ]]; then
  PROJECT_DIR="${2:?--project にはディレクトリを指定してください}"
  mkdir -p "$PROJECT_DIR/.claude"
  TARGET_SETTINGS="$PROJECT_DIR/.claude/settings.json"
fi

echo "==> ヘルパーをビルドします"
mkdir -p "$BIN_DIR"
swiftc -O "$SCRIPT_DIR/src/sjev-helper.swift" -o "$BIN_DIR/sjev-helper"
cp "$SCRIPT_DIR/bin/sjev" "$BIN_DIR/sjev"
chmod +x "$BIN_DIR/sjev" "$BIN_DIR/sjev-helper"

mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"

echo "==> 設定ファイル: $TARGET_SETTINGS"
if [[ ! -f "$TARGET_SETTINGS" ]]; then
  mkdir -p "$(dirname "$TARGET_SETTINGS")"
  echo '{}' > "$TARGET_SETTINGS"
fi

BACKUP="${TARGET_SETTINGS}.bak-$(date +%Y%m%d%H%M%S)"
cp "$TARGET_SETTINGS" "$BACKUP"
echo "==> バックアップ: $BACKUP"

SESSION_CMD="$BIN_DIR/sjev ensure >/dev/null 2>&1 || true"
HOOK_CMD="$BIN_DIR/sjev hook"

if ! python3 - "$TARGET_SETTINGS" "$SESSION_CMD" "$HOOK_CMD" <<'PYEOF'
import json
import os
import sys

path, session_cmd, hook_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

hooks = data.setdefault("hooks", {})


def has_command(entries, cmd):
    for group in entries:
        for h in group.get("hooks", []):
            if h.get("command") == cmd:
                return True
    return False


session_list = hooks.setdefault("SessionStart", [])
if not has_command(session_list, session_cmd):
    session_list.append({"hooks": [{"type": "command", "command": session_cmd}]})

prompt_list = hooks.setdefault("UserPromptSubmit", [])
if not has_command(prompt_list, hook_cmd):
    prompt_list.append({"hooks": [{"type": "command", "command": hook_cmd}]})

tmp_path = path + ".tmp-sjev"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp_path, path)
PYEOF
then
  echo "設定ファイルの書き換えに失敗しました。バックアップから戻すには: cp \"$BACKUP\" \"$TARGET_SETTINGS\""
  exit 1
fi

echo "==> フックを追記しました(既存フックは残しています)"
echo "==> 見張りを起動します"
"$BIN_DIR/sjev" ensure

echo "完了。画面収録の許可を求められたら許可してください。"
echo "止めるには: $BIN_DIR/sjev pause 9999h  (または ./uninstall.sh)"
