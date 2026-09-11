#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/riftos-source-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p \
  "$FIXTURE/android/app/src/main/java/com/riftos/app" \
  "$FIXTURE/apps/riftdev" \
  "$FIXTURE/src" \
  "$FIXTURE/scripts" \
  "$FIXTURE/workspace-live"

touch \
  "$FIXTURE/index.html" \
  "$FIXTURE/android/app/build.gradle.kts" \
  "$FIXTURE/android/riftos-debug.keystore.b64" \
  "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftMcpRuntime.kt" \
  "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftMcpServer.kt" \
  "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftToolSandbox.kt"

printf '%s\n' 'class RiftBrowserMcpAppBridge' \
  > "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftBrowserMcpAppBridge.kt"
printf '%s\n' 'class RiftBrowserWindow' \
  > "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftBrowserWindow.kt"
printf '%s\n' 'const tool = "rift_workspace_exec"' \
  > "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftToolHost.kt"
printf '%s\n' 'export const mcp = true;' > "$FIXTURE/src/riftmcp-system.js"
printf '%s\n' 'export const ok = true;' > "$FIXTURE/src/valid.js"
printf '%s\n' '{"scripts":{"check":"node --check check.js"}}' > "$FIXTURE/apps/riftdev/package.json"
printf '%s\n' 'const ok = true;' > "$FIXTURE/apps/riftdev/check.js"

"$CHECK" policy "$FIXTURE"
"$CHECK" syntax "$FIXTURE"

cp "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftMcpServer.kt" "$FIXTURE/server.kt"
rm "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftMcpServer.kt"
if "$CHECK" policy "$FIXTURE" >/dev/null 2>&1; then
  echo "missing required source was accepted" >&2
  exit 1
fi
mv "$FIXTURE/server.kt" "$FIXTURE/android/app/src/main/java/com/riftos/app/RiftMcpServer.kt"

mkdir -p "$FIXTURE/android/app/src/main/assets"
touch "$FIXTURE/android/app/src/main/assets/riftbrowser-mcp-app.js"
if "$CHECK" policy "$FIXTURE" >/dev/null 2>&1; then
  echo "removed page-injection asset was accepted" >&2
  exit 1
fi
rm "$FIXTURE/android/app/src/main/assets/riftbrowser-mcp-app.js"

printf '%s\n' 'const broken = ;' > "$FIXTURE/src/valid.js"
if "$CHECK" syntax "$FIXTURE" >/dev/null 2>&1; then
  echo "invalid JavaScript was accepted" >&2
  exit 1
fi

echo "RiftOS source-check regression tests passed."
