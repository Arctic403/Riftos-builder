#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:?usage: riftos-build.sh <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
LOG_DIR="${RUNNER_TEMP:?}/riftos-private-logs"
OUT_DIR="${RUNNER_TEMP:?}/riftos-output"
mkdir -p "$LOG_DIR" "$OUT_DIR"

# Fail before the expensive Android build if the builder-side smoke gate itself is malformed.
bash -n "$SCRIPT_DIR/verify-riftos-apk.sh"

cd "$SOURCE_DIR"
echo "Building RiftOS ${SOURCE_SHA:-unknown}."
if [ -n "${SOURCE_SHA:-}" ]; then
  ACTUAL_SHA="$(git rev-parse HEAD)"
  test "$ACTUAL_SHA" = "$SOURCE_SHA" || {
    echo "Source SHA mismatch: expected $SOURCE_SHA, got $ACTUAL_SHA" >&2
    exit 1
  }
fi

# A matching HEAD is not enough: source validation must run against the exact checked-out tree.
# Fail loudly if any tracked or untracked file drifted after actions/checkout instead of labeling
# mutated bytes with the resolved SOURCE_SHA in the private failure bundle.
{
  echo "head=$(git rev-parse HEAD)"
  echo "status:"
  git status --porcelain=v1 --untracked-files=all
} >"$LOG_DIR/source-integrity.log"
if ! git diff --quiet HEAD -- || [ -n "$(git status --porcelain=v1 --untracked-files=all)" ]; then
  echo 'RiftOS source tree drifted after checkout; refusing to run source checks against mutated bytes.' >&2
  git status --short --untracked-files=all >&2 || true
  exit 1
fi

# Validate the Builder's DEX-verifier assumption against the exact source contract before
# source tests/Gradle: every mandatory Kotlin filename must declare a matching top-level
# class/object/interface because verify-riftos-apk.sh derives that DEX descriptor from the file name.
gradle_contract="android/app/build.gradle.kts"
for required_gradle_contract in \
  'namespace = "com.riftos.app"' \
  'applicationId = "com.riftos.app"' \
  'compileSdk = 36' \
  'minSdk = 26' \
  'targetSdk = 36' \
  'JavaVersion.VERSION_17' \
  'getByName("release") { isMinifyEnabled = false }'; do
  grep -Fq "$required_gradle_contract" "$gradle_contract" || {
    echo "Builder contract is stale: expected Gradle contract missing: $required_gradle_contract" >&2
    exit 1
  }
done
mapfile -t required_native_sources < <(
  sed -nE 's/.*"(src\/main\/java\/com\/riftos\/app\/[A-Za-z0-9_]+\.kt)".*/\1/p' "$gradle_contract"
)
test "${#required_native_sources[@]}" -gt 0 || { echo 'Builder contract preflight found no mandatory Kotlin sources.' >&2; exit 1; }
for source_rel in "${required_native_sources[@]}"; do
  source="android/app/$source_rel"
  test -f "$source" || { echo "Builder contract preflight missing mandatory Kotlin source: $source_rel" >&2; exit 1; }
  class_name="${source_rel##*/}"
  class_name="${class_name%.kt}"
  if ! grep -Eq "^[[:space:]]*((public|private|internal|protected)[[:space:]]+)?((data|sealed|enum|annotation|value)[[:space:]]+)?(class|object|interface)[[:space:]]+${class_name}([[:space:]<(::{]|$)" "$source"; then
    echo "Builder DEX verifier assumption is stale: $source_rel does not declare top-level $class_name." >&2
    exit 1
  fi
done

: "${RIFT_SIGN_STORE:?Release signing identity required}"
: "${RIFT_SIGN_ALIAS:?Release key alias required}"
export RIFT_SIGN_STORE_PASS="${RIFT_SIGN_STORE_PASS:?Release store password required}"
export RIFT_SIGN_KEY_PASS="${RIFT_SIGN_KEY_PASS:?Release key password required}"

if ! npm run check >"$LOG_DIR/source-check.log" 2>&1; then
  echo 'Source checks failed; APK build stopped.' >&2
  exit 1
fi

if ! gradle -p android --stacktrace \
    :app:verifyRiftOsAndroidSources \
    :app:validateRiftBrowserWebViewOwnership \
    --no-daemon >"$LOG_DIR/gradle-validation.log" 2>&1; then
  echo "RiftOS Gradle validation failed before compilation. Detailed log will be returned privately." >&2
  exit 1
fi

if ! gradle -p android --stacktrace --build-cache :app:assembleRelease --no-daemon \
    >"$LOG_DIR/android-build.log" 2>&1; then
  echo "RiftOS Android compilation/packaging failed. Detailed log will be returned privately." >&2
  exit 1
fi

BUILD_TOOLS="${ANDROID_HOME:?}/build-tools/36.0.0"
UNSIGNED="android/app/build/outputs/apk/release/app-release-unsigned.apk"
ALIGNED="$RUNNER_TEMP/RiftOS-Android-aligned.apk"
FINAL="$OUT_DIR/RiftOS-Android-debug.apk"

test -f "$UNSIGNED" || { echo "Gradle did not produce $UNSIGNED" >&2; exit 1; }
"$BUILD_TOOLS/zipalign" -p -f 4 "$UNSIGNED" "$ALIGNED"
"$BUILD_TOOLS/apksigner" sign \
  --ks "${RIFT_SIGN_STORE:?}" \
  --ks-key-alias "${RIFT_SIGN_ALIAS:?}" \
  --ks-pass "env:RIFT_SIGN_STORE_PASS" \
  --key-pass "env:RIFT_SIGN_KEY_PASS" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled false \
  --v4-signing-enabled false \
  --out "$FINAL" "$ALIGNED"

"$BUILD_TOOLS/zipalign" -c -v 4 "$FINAL" >"$LOG_DIR/alignment.log" 2>&1
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$FINAL" >"$LOG_DIR/signature.log" 2>&1

if ! bash "$SCRIPT_DIR/verify-riftos-apk.sh" "$FINAL" "$SOURCE_DIR" >"$LOG_DIR/apk-smoke.log" 2>&1; then
  echo "RiftOS APK packaging smoke check failed. Detailed log will be returned privately." >&2
  exit 1
fi
sha256sum "$FINAL" >"$LOG_DIR/apk-sha256.log"

echo "RiftOS Android APK built, packaged, signed and verified."
