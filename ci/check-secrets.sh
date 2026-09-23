#!/usr/bin/env bash
# Проверка: не попали ли ключи в коммит.
# Гоняй перед push (или в pre-commit):  bash ci/check-secrets.sh
# Код выхода 1 — найден похожий на секрет литерал. Значения в выводе маскируются.
set -uo pipefail
cd "$(dirname "$0")/.."

ALLOW_FILE="ci/secret-allowlist.txt"
# hex-строки нормальны: вендоренные библиотеки, схемы TL, тесты, бинарники
SKIP_RE='^(TMessagesProj/jni/|TMessagesProj_AppTests/tlscheme/|TMessagesProj_AppTests/src/|ci/check-secrets\.sh$|ci/apply-secrets\.sh$|ci/workflow.*\.yml$|ci/secret-allowlist\.txt$)|\.(jar|aar|keystore|jks|so|png|jpg|webp|pack|ttf|zip|svg)$'
# где вообще может лежать api_hash
HEX_RE='BuildVars\.java$|gradle\.properties$|google-services\.json$|agconnect-services\.json$|AndroidManifest.*\.xml$|\.gradle$|\.properties$|^ci/'

allow=()
if [ -f "$ALLOW_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    allow+=("$line")
  done < "$ALLOW_FILE"
fi

mapfile -t files < <(git ls-files | grep -Ev "$SKIP_RE")
[ ${#files[@]} -eq 0 ] && { echo "== нечего проверять"; exit 0; }
found=0

clean() { printf '%s' "${1//\"/}" | sed -E "s/^['\"]//; s/['\"]$//"; }

report() { # $1=file $2=line $3=value
  local v; v="$(clean "$3")"
  local a; for a in ${allow[@]+"${allow[@]}"}; do [ "$v" = "$a" ] && return 0; done
  echo "ПОДОЗРЕНИЕ: $1:$2 -> ${v:0:6}… (значение скрыто)"
  found=1
}

scan() { # $1=regex(pcre) $2=file filter (опц.)
  local pat="$1" filt="${2:-}" flist
  if [ -n "$filt" ]; then
    flist="$(printf '%s\n' "${files[@]}" | grep -E "$filt")"
  else
    flist="$(printf '%s\n' "${files[@]}")"
  fi
  [ -z "$flist" ] && return 0
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    report "${hit%%:*}" "$(printf '%s' "$hit" | cut -d: -f2)" "${hit#*:*:}"
  done < <(printf '%s\n' "$flist" | xargs -r grep -nIHPo -- "$pat" 2>/dev/null)
}

# --- секреты, которые не должны встречаться нигде ---
scan 'AIza[0-9A-Za-z_-]{35}'                                   # Google API key
scan '[0-9]{8,10}:[A-Za-z0-9_-]{35}'                           # Telegram bot token
scan '-----BEGIN [A-Z ]*PRIVATE KEY-----'                      # приватные ключи
scan 'gh[pousr]_[A-Za-z0-9]{36,}'                              # GitHub-токены
scan 'sk-[A-Za-z0-9]{20,}'                                     # ключи LLM-сервисов
scan 'xox[abprs]-[A-Za-z0-9-]{10,}'                            # Slack
scan '(?<="client_secret"\s*:\s*")[^"]{16,}'                   # json client_secret
scan '(?<=client_secret=)[^\s&"]{16,}'                         # query client_secret
# --- значения, имеющие смысл только в определённых файлах ---
scan '[0-9a-f]{32}' "$HEX_RE"                                  # api_hash (32 hex)
scan '(?<=RELEASE_STORE_PASSWORD=)[^\s]{6,}' "$HEX_RE"
scan '(?<=RELEASE_KEY_PASSWORD=)[^\s]{6,}' "$HEX_RE"

if [ "$found" = "1" ]; then
  echo
  echo "!! Похоже, в трекнутых файлах есть секрет."
  echo "   Секреты держи в Actions Secrets (см. ci/README.md), а заведомо публичные"
  echo "   значения вписывай в $ALLOW_FILE."
  exit 1
fi

echo "== чисто: секретов в трекнутых файлах нет (проверено файлов: ${#files[@]})"
