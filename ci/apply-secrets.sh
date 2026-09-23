#!/usr/bin/env bash
# Подставляет секреты из переменных окружения в файлы ПЕРЕД сборкой.
# Смысл: ключи живут только в GitHub Actions Secrets (Settings → Secrets and variables → Actions)
# и никогда не попадают в коммиты. Если переменная не задана — файл не трогаем, сборка идёт как есть.
#
# Переменные (все опциональны):
#   VLAL_APP_ID               свой api_id с my.telegram.org   (int)
#   VLAL_APP_HASH             свой api_hash с my.telegram.org (строка)
#   VLAL_GOOGLE_SERVICES_B64  base64 от своего google-services.json
#   VLAL_KEYSTORE_B64         base64 от своего release.keystore (.jks)
#   VLAL_KEYSTORE_PASSWORD    пароль хранилища
#   VLAL_KEY_ALIAS            алиас ключа
#   VLAL_KEY_PASSWORD         пароль ключа
#
# ВАЖНО: скрипт ничего не печатает из секретов. Не включай сюда `set -x`.
set -euo pipefail
cd "$(dirname "$0")/.."

BV="TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java"
GP="gradle.properties"
KS="TMessagesProj/config/release.keystore"

esc() { printf '%s' "$1" | sed -e 's/[&\\|]/\\&/g'; }
b64d() { base64 -d 2>/dev/null || base64 --decode; }
changed=0

if [ -n "${VLAL_APP_ID:-}" ]; then
  sed -i -E "s|(public static int APP_ID = )[0-9]+;|\1${VLAL_APP_ID};|" "$BV"
  changed=1
fi

if [ -n "${VLAL_APP_HASH:-}" ]; then
  sed -i -E "s|(public static String APP_HASH = \")[^\"]*(\";)|\1$(esc "$VLAL_APP_HASH")\2|" "$BV"
  changed=1
fi

if [ -n "${VLAL_GOOGLE_SERVICES_B64:-}" ]; then
  printf '%s' "$VLAL_GOOGLE_SERVICES_B64" | b64d > TMessagesProj_App/google-services.json
  printf '%s' "$VLAL_GOOGLE_SERVICES_B64" | b64d > TMessagesProj/google-services.json
  changed=1
fi

if [ -n "${VLAL_KEYSTORE_B64:-}" ]; then
  printf '%s' "$VLAL_KEYSTORE_B64" | b64d > "$KS"
  echo "== подставлен свой release.keystore"
  changed=1
fi

[ -n "${VLAL_KEYSTORE_PASSWORD:-}" ] && { sed -i -E "s|^(RELEASE_STORE_PASSWORD=).*|\1$(esc "$VLAL_KEYSTORE_PASSWORD")|" "$GP"; changed=1; }
[ -n "${VLAL_KEY_ALIAS:-}" ] && { sed -i -E "s|^(RELEASE_KEY_ALIAS=).*|\1$(esc "$VLAL_KEY_ALIAS")|" "$GP"; changed=1; }
[ -n "${VLAL_KEY_PASSWORD:-}" ] && { sed -i -E "s|^(RELEASE_KEY_PASSWORD=).*|\1$(esc "$VLAL_KEY_PASSWORD")|" "$GP"; changed=1; }

if [ "$changed" = "1" ]; then
  echo "== секреты из Actions Secrets подставлены (значения в лог не выводятся)"
else
  echo "== VLAL_* не заданы — собираем на том, что лежит в репозитории (тестовые ключи Telegram)"
fi
