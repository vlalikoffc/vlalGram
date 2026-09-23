#!/usr/bin/env bash
# vlalGram: сборка APK (GitHub Actions или любая Linux-машина с Android SDK).
#
# Переменные окружения:
#   MODULE   TMessagesProj_App | TMessagesProj_AppStandalone   (по умолчанию TMessagesProj_App)
#   ABI      arm64-v8a | all                                    (по умолчанию arm64-v8a)
#   VARIANT  afatRelease | afatDebug | ...                      (по умолчанию afatRelease)
#
# Результат: APK-файлы в ./out/
set -euo pipefail

MODULE="${MODULE:-TMessagesProj_App}"
ABI="${ABI:-arm64-v8a}"
VARIANT="${VARIANT:-afatRelease}"
NDK_VERSION="27.2.12479018"
CMAKE_VERSION="3.22.1"
BUILD_TOOLS="36.0.0"
PLATFORM="android-36"

cd "$(dirname "$0")/.."
echo "== vlalGram build: module=$MODULE variant=$VARIANT abi=$ABI"
echo "== диск до чистки:"; df -h / | tail -1

# ---------- 1. Java ----------
if [ -n "${JAVA_HOME_17_X64:-}" ]; then
  export JAVA_HOME="$JAVA_HOME_17_X64"
elif [ -z "${JAVA_HOME:-}" ] && [ -d /usr/lib/jvm/temurin-17-jdk-amd64 ]; then
  export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
fi
export PATH="${JAVA_HOME:-}/bin:$PATH"
java -version 2>&1 | head -3 || { echo "!! Нет JDK 17+"; exit 1; }

# ---------- 2. Место на диске ----------
# Сборка Telegram тяжёлая (JNI + R8), чистим мусор образа раннера.
sudo rm -rf /usr/share/dotnet /opt/ghc /usr/share/swift /usr/local/.ghcup /usr/local/share/boost \
  "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/system-images \
  "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/ndk \
  "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/sources 2>/dev/null || true
echo "== диск после чистки:"; df -h / | tail -1

# ---------- 3. Android SDK / NDK / CMake ----------
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
export ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK"
SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
[ -x "$SDKMANAGER" ] || SDKMANAGER="$(command -v sdkmanager || true)"
[ -n "$SDKMANAGER" ] || { echo "!! Не найден sdkmanager"; exit 1; }

yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" --install "platform-tools" "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS" \
  "ndk;$NDK_VERSION" "cmake;$CMAKE_VERSION"
echo "sdk.dir=$SDK" > local.properties

# ---------- 4. Подмодули (ffmpeg, boringssl, td, media и т.д.) ----------
if [ ! -f TMessagesProj/jni/third_party/boringssl/CMakeLists.txt ] || [ -f .gitmodules ]; then
  git submodule sync --recursive
  git submodule update --init --recursive --depth 1 --jobs 4 \
    || git submodule update --init --recursive --jobs 4
fi

# ---------- 5. Ограничение ABI (сборка всех 4 ABI не влезает в раннер) ----------
if [ "$ABI" != "all" ]; then
  if grep -q '"armeabi-v7a", "arm64-v8a", "x86", "x86_64"' "$MODULE/build.gradle"; then
    sed -i "s/\"armeabi-v7a\", \"arm64-v8a\", \"x86\", \"x86_64\"/\"$ABI\"/g" "$MODULE/build.gradle"
  fi
  echo "== abiFilters после патча:"; grep -n 'abiFilters' "$MODULE/build.gradle" || true
fi

# ---------- 6. Сборка ----------
chmod +x gradlew
TASK=":${MODULE}:assemble${VARIANT^}"
echo "== gradle $TASK"
./gradlew --no-daemon --stacktrace --warning-mode=summary \
  -Dorg.gradle.jvmargs="-Xmx6g -XX:MaxMetaspaceSize=1g" \
  "$TASK"

# ---------- 7. Результат ----------
mkdir -p out
find "$MODULE/build/outputs/apk" -name '*.apk' -print -exec cp -f {} out/ \;
if ! ls out/*.apk >/dev/null 2>&1; then echo "!! APK не найден"; exit 1; fi
echo "== готово:"
ls -lh out/*.apk
sha256sum out/*.apk || true
