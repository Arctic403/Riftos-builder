#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:?usage: riftos-build.sh <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
LOG_DIR="${RUNNER_TEMP:?}/riftos-private-logs"
OUT_DIR="${RUNNER_TEMP:?}/riftos-output"
mkdir -p "$LOG_DIR" "$OUT_DIR"

for required_command in timeout gradle git grep sed sha256sum python3 dpkg-deb readelf patchelf; do
  command -v "$required_command" >/dev/null 2>&1 || {
    echo "Builder runtime is missing required command: $required_command" >&2
    exit 1
  }
done
SOURCE_CHECK_TIMEOUT="${SOURCE_CHECK_TIMEOUT:-12m}"
GRADLE_VALIDATE_TIMEOUT="${GRADLE_VALIDATE_TIMEOUT:-6m}"
GRADLE_BUILD_TIMEOUT="${GRADLE_BUILD_TIMEOUT:-20m}"
APK_VERIFY_TIMEOUT="${APK_VERIFY_TIMEOUT:-3m}"

# Fail before the expensive Android build if Builder-owned gates are malformed.
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

# RiftOS is a platform-only repository. Legacy npm/browser tests are NOT host inputs.
# Builder-owned validation enforces host-only layout and OS security contracts.
python3 "$SCRIPT_DIR/validate-platform-source.py" "$SOURCE_DIR" \
  >"$LOG_DIR/source-layout.log" 2>&1 || {
  echo 'Builder platform-only source layout validation failed.' >&2
  exit 1
}

# Host-only preflight. Embedded Core/Shell code still compiled for
# compatibility is FROZEN: do not re-run its E0/E1/C1 historical milestone tests.
# The source validator owns Android host/ABI/service closure and is run above.
echo 'RiftOS Builder: host-only source, security and external-component ABI checks.'
host_src='android/app/src/main/java/com/riftos/app'
manifest_src='android/app/src/main/AndroidManifest.xml'
gradle_src='android/app/build.gradle.kts'
test -f "$gradle_src" && test -f "$manifest_src" || {
  echo 'RiftOS host Gradle/manifest missing.' >&2; exit 1;
}
for required_host_source in \
  RiftCoreApplication.kt RiftShellActivity.kt \
  RiftHostComponentAbiV1.kt RiftShellComponentAbiV1.kt \
  RiftCoreCandidateSwitch.kt RiftShellCandidateSwitch.kt \
  RiftProtectedComponentManifest.kt RiftProtectedDexVerifier.kt \
  RiftProtectedComponentInstaller.kt RiftProtectedRevisionRecovery.kt \
  RiftManualRecoveryStore.kt RiftManualRecoveryActivity.kt \
  RiftCoreRecoverySupervisorService.kt RiftCoreSurfaceIpcProvider.kt \
  RiftHostExternalAppBinderV1.kt RiftMcpServer.kt RiftMcpRelayClient.kt \
  RiftMcpOperationJournal.kt RiftToolHost.kt RiftVortexLocalAgent.kt \
  RiftLocalAgentBatch.kt RiftWorkspaceRecords.kt RiftWorkspaceWatcher.kt \
  RiftVolumePaths.kt RiftNativeGit.kt RiftRappCapabilityBroker.kt; do
  test -f "$host_src/$required_host_source" || {
    echo "Missing APK-owned host source: $required_host_source" >&2; exit 1;
  }
done
for required_host_contract in \
  'interface RiftCoreComponentV1' \
  'interface RiftShellGraphicalComponentV1' \
  'interface RiftShellPlatformServicesV1' \
  'interface RiftShellPlatformServicesV2'; do
  grep -Fq "$required_host_contract" "$host_src/RiftHostComponentAbiV1.kt" \
    "$host_src/RiftShellComponentAbiV1.kt" || {
    echo "Missing external component host ABI: $required_host_contract" >&2; exit 1;
  }
done
for required_recovery in \
  'RiftManualRecoveryActivity' 'RiftCoreRecoverySupervisorService' \
  'RiftVortexAccessibilityService' 'RiftMcpActivity' \
  'RiftCoreSurfaceIpcProvider' 'androidx.core.content.FileProvider'; do
  grep -Fq "$required_recovery" "$manifest_src" || {
    echo "Missing Android host/Recovery surface: $required_recovery" >&2; exit 1;
  }
done
for required_build_gate in \
  ':app:verifyRiftOsAndroidSources' \
  ':app:validateRiftBrowserWebViewOwnership'; do
  # Both are invoked below as part of mandatory Gradle validation.
  grep -Fq "$required_build_gate" "$SCRIPT_DIR/riftos-build.sh" || {
    echo "Missing mandatory host Gradle gate: $required_build_gate" >&2; exit 1;
  }
done
# Keep the user-owned manual sign/verify pipeline below unchanged.
# No Core/Shell component construction, activation or backup promotion here.

: "${RIFT_SIGN_STORE:?Release signing identity required}"
: "${RIFT_SIGN_ALIAS:?Release key alias required}"
export RIFT_SIGN_STORE_PASS="${RIFT_SIGN_STORE_PASS:?Release store password required}"
export RIFT_SIGN_KEY_PASS="${RIFT_SIGN_KEY_PASS:?Release key password required}"

if ! timeout --signal=TERM --kill-after=30s "$SOURCE_CHECK_TIMEOUT" \
    python3 "$SCRIPT_DIR/validate-platform-source.py" "$SOURCE_DIR" \
    >"$LOG_DIR/source-check.log" 2>&1; then
  echo "Builder-owned platform source checks failed or exceeded $SOURCE_CHECK_TIMEOUT; APK build stopped." >&2
  exit 1
fi

# Native runtime/editor hosts must be rebuilt from the checked-out source.
# Discard CMake/native packaging intermediates that can survive worker reuse across source revisions.
rm -rf \
  android/app/.cxx \
  android/.cxx \
  android/app/build/intermediates/cxx \
  android/app/build/intermediates/merged_native_libs \
  android/app/build/intermediates/stripped_native_libs

if ! timeout --signal=TERM --kill-after=30s "$GRADLE_VALIDATE_TIMEOUT" \
    gradle -p android --stacktrace \
      :app:verifyRiftOsAndroidSources \
      :app:validateRiftBrowserWebViewOwnership \
      --no-daemon >"$LOG_DIR/gradle-validation.log" 2>&1; then
  echo "RiftOS Gradle validation failed or exceeded $GRADLE_VALIDATE_TIMEOUT before compilation. Detailed log will be returned privately." >&2
  exit 1
fi

if ! timeout --signal=TERM --kill-after=30s "$GRADLE_BUILD_TIMEOUT" \
    gradle -p android --stacktrace --no-build-cache :app:assembleRelease --no-daemon \
    >"$LOG_DIR/android-build.log" 2>&1; then
  echo "RiftOS Android compilation/packaging failed or exceeded $GRADLE_BUILD_TIMEOUT. Detailed log will be returned privately." >&2
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

if ! timeout --signal=TERM --kill-after=15s "$APK_VERIFY_TIMEOUT" \
    bash "$SCRIPT_DIR/verify-riftos-apk.sh" "$FINAL" "$SOURCE_DIR" >"$LOG_DIR/apk-smoke.log" 2>&1; then
  echo "RiftOS APK packaging smoke check failed or exceeded $APK_VERIFY_TIMEOUT. Detailed log will be returned privately." >&2
  exit 1
fi
sha256sum "$FINAL" >"$LOG_DIR/apk-sha256.log"

echo "RiftOS Android APK built, packaged, signed and verified."
