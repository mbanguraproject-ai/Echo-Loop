#!/usr/bin/env bash
# Sets up a Linux machine (GitHub Codespaces, a cloud sandbox, a dev box) to build the
# Android app: JDK 21 if the installed Java is older, Android SDK command-line tools,
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
need node "Install Node.js 22 or newer."
need curl "Install curl."
need unzip "Install unzip."

# Capacitor 8 compiles for Java 21. If the machine's Java is older (or missing), install
# Eclipse Temurin 21 into ~/jdk-21 and point Gradle at it, leaving the system Java alone.
java_major() { "$1" -version 2>&1 | awk -F'"' '/version/ { split($2, v, "."); print (v[1] == "1" ? v[2] : v[1]); exit }'; }
JAVA_BIN="$(command -v java || true)"
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then JAVA_BIN="$JAVA_HOME/bin/java"; fi
major=0
if [ -n "$JAVA_BIN" ]; then major="$(java_major "$JAVA_BIN")"; fi
if [ "${major:-0}" -lt 21 ] 2>/dev/null; then
  JDK21="$HOME/jdk-21"
  if [ ! -x "$JDK21/bin/java" ]; then
    echo "Java ${major:-none} found; the build needs JDK 21. Installing Eclipse Temurin 21 into $JDK21"
    case "$(uname -m)" in aarch64|arm64) arch=aarch64 ;; *) arch=x64 ;; esac
    tmp="$(mktemp -d)"
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/21/ga/linux/$arch/jdk/hotspot/normal/eclipse" -o "$tmp/jdk.tar.gz"
    mkdir -p "$JDK21"
    tar -xzf "$tmp/jdk.tar.gz" -C "$JDK21" --strip-components=1
    rm -rf "$tmp"
  fi
  props="$HOME/.gradle/gradle.properties"
  mkdir -p "$HOME/.gradle"; touch "$props"
  grep -v '^org.gradle.java.home=' "$props" > "$props.tmp" || true
  echo "org.gradle.java.home=$JDK21" >> "$props.tmp"; mv "$props.tmp" "$props"
  echo "Gradle will build with $JDK21 (set in $props)"
  export JAVA_HOME="$JDK21"
  if [ -z "$(command -v java || true)" ]; then
    echo "No java on PATH: run 'export JAVA_HOME=$JDK21 PATH=$JDK21/bin:\$PATH' before building." >&2
  fi
else
  echo "Java $major found"
fi

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
echo "Output: EchoLoop-debug.apk in the project folder"
