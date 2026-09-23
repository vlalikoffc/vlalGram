#!/usr/bin/env bash
# Генерирует свой release.keystore прямо в Actions — без компьютера и без Termux.
# Запускается, если в workflow включена галка `generate_keystore`.
#
# Пароли берутся из секретов: VLAL_KEYSTORE_PASSWORD (обязательно), VLAL_KEY_ALIAS.
# Для PKCS12 пароль ключа обязан совпадать с паролем хранилища, так что VLAL_KEY_PASSWORD
# не нужен: используется VLAL_KEYSTORE_PASSWORD.
#
# Если VLAL_KEYSTORE_B64 уже задан — ничего не делаем, чужой ключ не перетираем.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${VLAL_KEYSTORE_B64:-}" ]; then
  echo "== VLAL_KEYSTORE_B64 задан — генерация не нужна, использую его"
  exit 0
fi

if [ -z "${VLAL_KEYSTORE_PASSWORD:-}" ]; then
  echo "!! Задай секрет VLAL_KEYSTORE_PASSWORD (любой пароль, который не жалко) —"
  echo "   иначе сгенерированный ключ будет нечем открыть. Settings → Secrets and variables → Actions."
  exit 1
fi

ALIAS="${VLAL_KEY_ALIAS:-vlalgram}"
mkdir -p out
rm -f out/release.keystore

# Пароль не печатаем и не подставляем в sh -c: только аргументами keytool.
keytool -genkeypair \
  -keystore out/release.keystore \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -storetype PKCS12 \
  -storepass "$VLAL_KEYSTORE_PASSWORD" \
  -keypass "$VLAL_KEYSTORE_PASSWORD" \
  -dname "CN=vlalGram, OU=vlalGram, O=vlalGram, L=Riga, C=LV" > /dev/null

cp out/release.keystore TMessagesProj/config/release.keystore
echo "== сгенерирован свой release.keystore (alias=$ALIAS, срок ~30 лет)"
echo "== он выложен артефактом vlal-keystore — скачай и храни: без него не будет обновлений «поверх»"
echo "== пароль для него: тот, что в секрете VLAL_KEYSTORE_PASSWORD"
