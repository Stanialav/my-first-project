#!/usr/bin/env bash
# Подключает чаты Cursor к уже существующему хранилищу Obsidian и обновляет их каждые 10 минут.
# Настройки Obsidian, плагины и остальные заметки не меняются.
# Запуск: curl -fsSL https://cdn.jsdelivr.net/gh/Stanialav/my-first-project@main/setup/mac-linux.sh | bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Stanialav/my-first-project.git}"
BRANCH="${BRANCH:-main}"
VAULT="${VAULT:-Stas}"
SUBFOLDER="${SUBFOLDER:-Входящие/Cursor}"
VAULT_PATH="${VAULT_PATH:-}"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nОШИБКА: %s\n' "$1" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) OBSIDIAN_CONFIG="$HOME/Library/Application Support/obsidian/obsidian.json" ;;
  *)      OBSIDIAN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json" ;;
esac

step "Проверяю Git"
if ! git --version >/dev/null 2>&1; then
  if [ "$(uname -s)" = Darwin ]; then
    xcode-select --install || true
    fail "Сейчас откроется окно установки инструментов разработчика (в них есть Git). Нажми «Установить», дождись конца и запусти эту команду ещё раз."
  fi
  fail "Git не установлен. Установи его (например: sudo apt install git) и запусти эту команду ещё раз."
fi

step "Ищу хранилище Obsidian «$VAULT»"
if [ -z "$VAULT_PATH" ] && [ -f "$OBSIDIAN_CONFIG" ] && command -v python3 >/dev/null 2>&1; then
  VAULT_PATH="$(python3 - "$OBSIDIAN_CONFIG" "$VAULT" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    vaults = json.load(fh).get("vaults", {})
found = [v["path"] for v in vaults.values() if os.path.basename(v.get("path", "").rstrip("/")) == sys.argv[2]]
print(found[0] if len(found) == 1 else "")
PY
)"
fi
if [ -z "$VAULT_PATH" ]; then
  printf 'Не нашёл хранилище «%s». Вставь полный путь к папке хранилища: ' "$VAULT"
  read -r VAULT_PATH </dev/tty
fi
[ -d "$VAULT_PATH" ] || fail "Папка $VAULT_PATH не найдена."
[ -d "$VAULT_PATH/.obsidian" ] || echo "Внимание: в $VAULT_PATH нет папки .obsidian. Проверь, что это хранилище Obsidian."
echo "Хранилище: $VAULT_PATH"

TARGET="$VAULT_PATH/$SUBFOLDER"
step "Подключаю чаты в $TARGET"
if [ -d "$TARGET/.git" ]; then
  git -C "$TARGET" pull --ff-only
elif [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET")" ]; then
  fail "Папка $TARGET уже есть и в ней что-то лежит. Ничего не трогаю: переименуй её или укажи другую папку."
else
  mkdir -p "$TARGET"
  git -C "$TARGET" init -q
  git -C "$TARGET" remote add origin "$REPO_URL"
  git -C "$TARGET" config core.sparseCheckout true
  printf '/chats/\n' > "$TARGET/.git/info/sparse-checkout"
  git -C "$TARGET" fetch -q --depth 50 origin "$BRANCH"
  git -C "$TARGET" checkout -q -B "$BRANCH" --track "origin/$BRANCH"
fi

if [ -d "$VAULT_PATH/.git" ]; then
  RULE="/$SUBFOLDER/"
  if ! grep -qxF "$RULE" "$VAULT_PATH/.gitignore" 2>/dev/null; then
    if [ -s "$VAULT_PATH/.gitignore" ] && [ -n "$(tail -c1 "$VAULT_PATH/.gitignore")" ]; then
      echo >> "$VAULT_PATH/.gitignore"
    fi
    echo "$RULE" >> "$VAULT_PATH/.gitignore"
    echo "Хранилище само под Git, поэтому добавил $RULE в его .gitignore."
  fi
fi

step "Включаю обновление каждые 10 минут"
GIT_BIN="$(command -v git)"
CRON_LINE="*/10 * * * * \"$GIT_BIN\" -C \"$TARGET\" pull --ff-only -q >/dev/null 2>&1 # cursor-chats-pull"
{ crontab -l 2>/dev/null | grep -v '# cursor-chats-pull' || true; echo "$CRON_LINE"; } | crontab -

cat <<EOF

Всё готово.
- Чаты лежат в хранилище «$VAULT»: $TARGET/chats
- В Obsidian они появятся сами, открывать ничего не нужно.
- Обновление: задача cron каждые 10 минут.
- Остальные заметки, настройки и плагины Obsidian не тронуты.
EOF
