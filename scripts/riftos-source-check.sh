#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?usage: riftos-source-check.sh <policy|syntax> <source-dir>}"
SOURCE_DIR="${2:?usage: riftos-source-check.sh <policy|syntax> <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
cd "$SOURCE_DIR"

fail() {
  echo "RiftOS source check failed: $*" >&2
  exit 1
}

require_file() {
  test -f "$1" || fail "missing required file: $1"
}

forbid_path() {
  test ! -e "$1" || fail "removed runtime path is present: $1"
}

check_policy() {
  local path
  local -a required=(
    index.html
    android/app/build.gradle.kts
    android/riftos-debug.keystore.b64
    android/app/src/main/assets/riftbrowser-mcp-app.js
    android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt
    android/app/src/main/java/com/riftos/app/RiftBrowserWindow.kt
    android/app/src/main/java/com/riftos/app/RiftMcpRuntime.kt
    android/app/src/main/java/com/riftos/app/RiftMcpServer.kt
    android/app/src/main/java/com/riftos/app/RiftToolHost.kt
    android/app/src/main/java/com/riftos/app/RiftToolSandbox.kt
    src/riftmcp-system.js
  )
  local -a forbidden=(
    services/rift-mcp-relay
    src/riftbridge-system.js
    src/riftai-workspace.js
    android/app/src/main/java/com/riftos/app/RiftMcpRelayClient.kt
    android/app/src/main/java/com/riftos/app/RiftMcpBridgeActivity.kt
    android/app/src/main/java/com/riftos/app/RiftMcpInitProvider.kt
  )

  for path in "${required[@]}"; do require_file "$path"; done
  for path in "${forbidden[@]}"; do forbid_path "$path"; done

  grep -Fq "rift_workspace_exec" android/app/src/main/java/com/riftos/app/RiftToolHost.kt \
    || fail "RiftToolHost does not expose rift_workspace_exec"

  local adapter=android/app/src/main/assets/riftbrowser-mcp-app.js
  grep -Fq "RiftMcpNative.postMessage" "$adapter" \
    || fail "ChatGPT connector does not call the native MCP bridge"
  grep -Fq "window.RiftMcpAppNative" "$adapter" \
    || fail "ChatGPT connector cannot receive native MCP responses"
  grep -Fq "postRpc('initialize'" "$adapter" \
    || fail "ChatGPT connector does not initialize MCP"
  grep -Fq "postRpc('tools/list'" "$adapter" \
    || fail "ChatGPT connector does not request the native tool manifest"
  grep -Fq "postRpc('tools/call'" "$adapter" \
    || fail "ChatGPT connector does not route calls to the native tool host"

  local bridge=android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt
  grep -Fq 'assets.open("riftbrowser-mcp-app.js")' "$bridge" \
    || fail "native bridge does not load the ChatGPT connector asset"
  grep -Fq "addDocumentStartJavaScript" "$bridge" \
    || fail "native bridge does not install the connector at document start"
  grep -Fq "evaluateJavascript(script" "$bridge" \
    || fail "native bridge has no fallback connector injection"

  if grep -Eqi 'api\.openai\.com|OPENAI_API_KEY|Authorization:[[:space:]]*Bearer|WebSocket|wss://' \
      "$adapter" \
      android/app/src/main/java/com/riftos/app/RiftBrowserWindow.kt \
      "$bridge" \
      src/riftmcp-system.js; then
    fail "remote model or relay path leaked into browser/native MCP connection"
  fi
}

check_syntax() {
  local checked=0
  local file
  while IFS= read -r -d '' file; do
    node --check "$file"
    checked=$((checked + 1))
  done < <(
    find src scripts apps/riftdev workspace-live android/app/src/main/assets -type f \
      \( -name '*.js' -o -name '*.mjs' \) -print0
  )
  test "$checked" -gt 0 || fail "no JavaScript sources found"
  npm --prefix apps/riftdev run check
}

case "$MODE" in
  policy) check_policy ;;
  syntax) check_syntax ;;
  *) fail "unknown mode: $MODE" ;;
esac
