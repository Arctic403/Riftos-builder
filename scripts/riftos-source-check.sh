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
    android/app/src/main/assets/riftbrowser-mcp-app.js
    android/app/src/main/java/com/riftos/app/RiftMcpRelayClient.kt
    android/app/src/main/java/com/riftos/app/RiftMcpBridgeActivity.kt
    android/app/src/main/java/com/riftos/app/RiftMcpInitProvider.kt
  )

  for path in "${required[@]}"; do require_file "$path"; done
  for path in "${forbidden[@]}"; do forbid_path "$path"; done

  grep -Fq "rift_workspace_exec" android/app/src/main/java/com/riftos/app/RiftToolHost.kt \
    || fail "RiftToolHost does not expose rift_workspace_exec"

  if grep -Eqi 'api\.openai\.com|OPENAI_API_KEY|Authorization:[[:space:]]*Bearer' \
      android/app/src/main/java/com/riftos/app/RiftBrowserWindow.kt \
      android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt \
      src/riftmcp-system.js; then
    fail "direct model API path leaked into browser/local MCP source"
  fi

  if grep -Eq 'addDocumentStartJavaScript|evaluateJavascript\(script' \
      android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt; then
    fail "removed ChatGPT page-injection path is still active"
  fi
}

check_syntax() {
  local checked=0
  local file
  while IFS= read -r -d '' file; do
    node --check "$file"
    checked=$((checked + 1))
  done < <(
    find src scripts apps/riftdev workspace-live -type f \
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
