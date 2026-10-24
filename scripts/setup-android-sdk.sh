#!/usr/bin/env bash
# Sets up a Linux machine to build the Android app: Android SDK command-line tools,
# platform 36, build-tools 36 and platform-tools, npm dependencies, and
# android/local.properties pointing at the SDK. Safe to re-run; finished steps are skipped.
#
# Usage: bash scripts/setup-android-sdk.sh [--maven-mirror]
#   --maven-mirror  route Maven Central through Google's mirror, for hosts that Central
#                   rate-limits (cloud sandboxes). Writes ~/.gradle/init.d/maven-mirror.gradle.
# Set ANDROID_HOME to choose the SDK location (default: ~/android-sdk).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"   # cmdline-tools 23.0
PACKAGES=("platforms;android-36" "build-tools;36.0.0" "platform-tools")
MIRROR=0
for arg in "$@"; do
  case "$arg" in
    --maven-mirror) MIRROR=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. $2" >&2; exit 1; }; }
need java "Install JDK 21 (for example: sudo apt-get install -y openjdk-21-jdk-headless)."
need node "Install Node.js 22 or newer."
need curl "Install curl."
need unzip "Install unzip."

SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  echo "Installing Android command-line tools into $SDK"
  tmp="$(mktemp -d)"
  curl -fsSL "https://dl.google.com/android/repository/$TOOLS_ZIP" -o "$tmp/tools.zip"
  unzip -q "$tmp/tools.zip" -d "$tmp"
  mkdir -p "$SDK/cmdline-tools"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$tmp"
fi

missing=()
for p in "${PACKAGES[@]}"; do [ -d "$SDK/${p//;//}" ] || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "Installing SDK packages: ${missing[*]}"
  yes | "$SDKMANAGER" --sdk_root="$SDK" --licenses >/dev/null || true
  "$SDKMANAGER" --sdk_root="$SDK" "${missing[@]}"
else
  echo "Android SDK packages already installed in $SDK"
fi

echo "sdk.dir=$SDK" > "$ROOT/android/local.properties"

if [ "$MIRROR" = 1 ]; then
  mkdir -p "$HOME/.gradle/init.d"
  cat > "$HOME/.gradle/init.d/maven-mirror.gradle" <<'GRADLE'
// Route Maven Central through Google's mirror (Central rate-limits some hosts).
def MIRROR = 'https://maven-central.storage-download.googleapis.com/maven2/'
def fix = { RepositoryHandler repos ->
  repos.all { r ->
    if (r instanceof MavenArtifactRepository && r.url.toString().startsWith('https://repo.maven.apache.org')) r.url = MIRROR
  }
}
settingsEvaluated { s -> fix(s.pluginManagement.repositories); fix(s.dependencyResolutionManagement.repositories) }
allprojects { fix(buildscript.repositories); fix(repositories) }
GRADLE
  echo "Maven Central mirror enabled (~/.gradle/init.d/maven-mirror.gradle)"
fi

if [ ! -d "$ROOT/node_modules" ]; then (cd "$ROOT" && npm ci); fi

echo
echo "Ready. Build a test APK with: npm run apk"
echo "Output: android/app/build/outputs/apk/debug/app-debug.apk"
