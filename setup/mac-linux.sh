#!/usr/bin/env bash
# Скачивает хранилище чатов на компьютер и подключает его к Obsidian.
# Запуск: curl -fsSL https://raw.githubusercontent.com/Stanialav/my-first-project/main/setup/mac-linux.sh | bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Stanialav/my-first-project.git}"
BRANCH="${BRANCH:-main}"
DEST="${DEST:-$HOME/Documents/my-first-project}"
PLUGIN_URL="https://github.com/Vinzent03/obsidian-git/releases/latest/download"
VAULT_NAME="$(basename "$DEST")"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nОШИБКА: %s\n' "$1" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) OS=mac; OBSIDIAN_CONFIG="$HOME/Library/Application Support/obsidian/obsidian.json" ;;
  *)      OS=linux; OBSIDIAN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json" ;;
esac

step "Проверяю Git"
if ! git --version >/dev/null 2>&1; then
  if [ "$OS" = mac ]; then
    xcode-select --install || true
    fail "Сейчас откроется окно установки инструментов разработчика (в них есть Git). Нажми «Установить», дождись конца и запусти эту команду ещё раз."
  fi
  fail "Git не установлен. Установи его (например: sudo apt install git) и запусти эту команду ещё раз."
fi

step "Проверяю Obsidian"
if [ "$OS" = mac ] && [ ! -d /Applications/Obsidian.app ] && [ ! -d "$HOME/Applications/Obsidian.app" ]; then
  if command -v brew >/dev/null 2>&1; then
    brew install --cask obsidian
  else
    echo "Obsidian не найден. Скачай его с https://obsidian.md и установи. Хранилище всё равно будет подготовлено."
  fi
fi

step "Скачиваю папку в $DEST"
mkdir -p "$(dirname "$DEST")"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
elif [ -e "$DEST" ]; then
  fail "Папка $DEST уже существует и это не копия репозитория. Переименуй её и запусти команду ещё раз."
else
  git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
fi
[ -d "$DEST/chats" ] || fail "В репозитории нет папки chats/. Сначала нажми «Merge» в pull request на GitHub."

step "Устанавливаю плагин Obsidian Git"
PLUGIN_DIR="$DEST/.obsidian/plugins/obsidian-git"
mkdir -p "$PLUGIN_DIR"
for f in main.js manifest.json styles.css; do
  curl -fsSL "$PLUGIN_URL/$f" -o "$PLUGIN_DIR/$f"
done

step "Добавляю хранилище в Obsidian"
if pgrep -xi obsidian >/dev/null 2>&1; then
  echo "Obsidian сейчас открыт, поэтому список хранилищ не изменён."
  echo "Закрой Obsidian и запусти команду ещё раз, или открой папку вручную: «Открыть папку как хранилище» → $DEST"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$OBSIDIAN_CONFIG" "$DEST" <<'PY'
import json, os, secrets, sys, time
config, dest = sys.argv[1], os.path.abspath(sys.argv[2])
data = {}
if os.path.exists(config):
    with open(config, encoding="utf-8") as fh:
        data = json.load(fh)
vaults = data.setdefault("vaults", {})
for v in vaults.values():
    v.pop("open", None)
existing = next((v for v in vaults.values() if os.path.abspath(v.get("path", "")) == dest), None)
if existing is None:
    existing = vaults.setdefault(secrets.token_hex(8), {"path": dest})
existing["ts"] = int(time.time() * 1000)
existing["open"] = True
os.makedirs(os.path.dirname(config), exist_ok=True)
with open(config, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False)
PY
  echo "Готово: хранилище «$VAULT_NAME» добавлено."
else
  echo "Не нашёл python3. Открой папку вручную: Obsidian → «Открыть папку как хранилище» → $DEST"
fi

step "Открываю Obsidian"
URI="obsidian://open?vault=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$VAULT_NAME" 2>/dev/null || echo "$VAULT_NAME")"
if [ "$OS" = mac ]; then
  open "$URI" 2>/dev/null || true
else
  (xdg-open "$URI" >/dev/null 2>&1 &) || true
fi

cat <<EOF

Всё готово.
- Папка: $DEST
- Если Obsidian спросит, доверять ли плагинам этого хранилища, нажми «Доверять автору и включить плагины».
- Новые чаты от агентов будут подтягиваться при запуске Obsidian и каждые 10 минут.
EOF
