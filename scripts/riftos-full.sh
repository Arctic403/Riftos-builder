#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:?usage: riftos-full.sh <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
LOG_DIR="${RUNNER_TEMP:?}/riftos-private-logs"
OUT_DIR="${RUNNER_TEMP:?}/riftos-output"
VERIFY_DIR="${RUNNER_TEMP:?}/riftos-verification"
mkdir -p "$LOG_DIR" "$OUT_DIR" "$VERIFY_DIR"

run_private() {
  local name="$1"
  shift
  local log="$LOG_DIR/${name}.log"
  echo "Running ${name}…"
  if ! "$@" >"$log" 2>&1; then
    echo "Stage failed: ${name}. Detailed log will be returned privately." >&2
    return 1
  fi
}

source_policy() {
  test ! -e services/rift-mcp-relay
  test ! -e src/riftbridge-system.js
  test ! -e android/app/src/main/java/com/riftos/app/RiftMcpRelayClient.kt
  test ! -e android/app/src/main/java/com/riftos/app/RiftMcpBridgeActivity.kt
  test ! -e android/app/src/main/java/com/riftos/app/RiftMcpInitProvider.kt
  test ! -e src/riftai-workspace.js
  test -f android/app/src/main/java/com/riftos/app/RiftMcpServer.kt
  test -f android/app/src/main/java/com/riftos/app/RiftMcpRuntime.kt
  test -f android/app/src/main/java/com/riftos/app/RiftToolHost.kt
  grep -Fq "rift_workspace_exec" android/app/src/main/java/com/riftos/app/RiftToolHost.kt
  if grep -Eqi 'api\.openai\.com|OPENAI_API_KEY|Authorization:[[:space:]]*Bearer' \
      android/app/src/main/assets/riftbrowser-mcp-app.js \
      android/app/src/main/java/com/riftos/app/RiftBrowserWindow.kt \
      android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt; then
    echo "Direct model API path leaked into ChatGPT Web / local MCP source" >&2
    return 1
  fi
}

verify_apk() {
  "$BUILD_TOOLS/zipalign" -c -v 4 "$FINAL"
  local verify_output badging dex_strings
  verify_output="$("$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$FINAL")"
  printf '%s\n' "$verify_output" | grep -Fq "Verified using v2 scheme (APK Signature Scheme v2): true"
  badging="$("$BUILD_TOOLS/aapt" dump badging "$FINAL")"
  printf '%s\n' "$badging" | grep -Fq "sdkVersion:'26'"
  printf '%s\n' "$badging" | grep -Fq "package: name='com.riftos.app'"
  unzip -p "$FINAL" assets/www/index.html | grep -Fq "SAMSUNG ANDROID"
  dex_strings="$(unzip -p "$FINAL" classes.dex | strings)"
  printf '%s\n' "$dex_strings" | grep -Fq "rift_workspace_exec"
  if unzip -l "$FINAL" | grep -Fq "assets/www/src/riftai-workspace.js"; then
    echo "Removed Rift AI workspace app leaked into APK" >&2
    return 1
  fi
  if unzip -l "$FINAL" | grep -Fq "assets/riftbrowser-chatgpt-agent.js"; then
    echo "Removed ChatGPT DOM agent leaked into APK" >&2
    return 1
  fi
  if printf '%s\n' "$dex_strings" | grep -Eq 'RiftMcpRelayClient|RiftMcpBridgeActivity|RiftMcpInitProvider|wss://your-relay'; then
    echo "Removed remote MCP runtime leaked into APK" >&2
    return 1
  fi
  if unzip -l "$FINAL" | grep -Fq "libllamaserver.so"; then
    echo "Removed local-AI runtime leaked into APK" >&2
    return 1
  fi
}

cd "$SOURCE_DIR"
test "$(git rev-parse HEAD)" = "${SOURCE_SHA:?}"
test -f android/app/build.gradle.kts
test -f android/riftos-debug.keystore.b64
test -f index.html

echo "Building private RiftOS ${SOURCE_SHA} for client ${CLIENT_ID:-unknown}."

# Private RiftOS is source-only. Build workflows belong in public Riftos-builder.
if [ -d .github/workflows ] && find .github/workflows -type f -print -quit | grep -q .; then
  echo "RiftOS source contains GitHub Actions workflows; refusing build. Use the Actions-free private-source model." >&2
  exit 2
fi

run_private source-policy source_policy
run_private source-check npm run check
run_private android-build gradle -p android --stacktrace --build-cache :app:assembleRelease --no-daemon

BUILD_TOOLS="${ANDROID_HOME:?}/build-tools/36.0.0"
UNSIGNED="android/app/build/outputs/apk/release/app-release-unsigned.apk"
ALIGNED="$RUNNER_TEMP/RiftOS-Android-aligned.apk"
FINAL="$OUT_DIR/RiftOS-Android-debug.apk"
test -f "$UNSIGNED"

run_private apk-align "$BUILD_TOOLS/zipalign" -p -f 4 "$UNSIGNED" "$ALIGNED"
run_private apk-sign "$BUILD_TOOLS/apksigner" sign \
  --ks "${RIFT_SIGN_STORE:?}" \
  --ks-key-alias "${RIFT_SIGN_ALIAS:?}" \
  --ks-pass "pass:${RIFT_SIGN_STORE_PASS:?}" \
  --key-pass "pass:${RIFT_SIGN_KEY_PASS:?}" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled false \
  --v4-signing-enabled false \
  --out "$FINAL" "$ALIGNED"

run_private apk-verify verify_apk

SHORT_SHA="${SOURCE_SHA:0:8}"
APK_SHA="$(sha256sum "$FINAL" | awk '{print $1}')"
APK_BYTES="$(stat -c '%s' "$FINAL")"

cat > "$OUT_DIR/build-manifest.json" <<EOF
{
  "source_sha": "${SOURCE_SHA}",
  "builder": "Arctic403/Riftos-builder",
  "builder_run_id": "${GITHUB_RUN_ID:-}",
  "client_id": "${CLIENT_ID:-}",
  "verification": "passed",
  "signing_mode": "${RIFT_SIGN_MODE:-unknown}",
  "apk": "RiftOS-Android-debug.apk",
  "apk_sha256": "${APK_SHA}",
  "apk_bytes": ${APK_BYTES},
  "artifact_policy": "riftos-private-prerelease-only"
}
EOF

printf 'source_sha=%s\nclient_id=%s\nbuilder_repo=%s\nbuilder_run_id=%s\nsigning_mode=%s\napk_sha256=%s\n' \
  "$SOURCE_SHA" "${CLIENT_ID:-}" "${GITHUB_REPOSITORY:-}" "${GITHUB_RUN_ID:-}" "${RIFT_SIGN_MODE:-unknown}" "$APK_SHA" > "$OUT_DIR/provenance.txt"

cp "$OUT_DIR/build-manifest.json" "$VERIFY_DIR/"
cp "$OUT_DIR/provenance.txt" "$VERIFY_DIR/"
cp -R "$LOG_DIR" "$VERIFY_DIR/logs"
(cd "$VERIFY_DIR" && zip -qr "$OUT_DIR/RiftOS-verification-${SHORT_SHA}.zip" .)
sha256sum "$OUT_DIR"/* > "$OUT_DIR/sha256sums.txt"

echo "RiftOS Android build verified for ${SOURCE_SHA}."
