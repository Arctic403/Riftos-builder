#!/usr/bin/env bash
set -euo pipefail

APK="${1:?usage: verify-riftos-apk.sh <apk> [source-dir]}"
SOURCE_DIR="${2:-$(pwd)}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
test -f "$APK" || { echo "APK not found: $APK" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo 'unzip is required for APK smoke validation.' >&2; exit 1; }
command -v cmp >/dev/null 2>&1 || { echo 'cmp is required for APK smoke validation.' >&2; exit 1; }

entries="$(unzip -Z1 "$APK")"
require_entry() {
  local entry="$1"
  if ! grep -Fxq "$entry" <<<"$entries"; then
    echo "APK smoke check failed: missing $entry" >&2
    exit 1
  fi
}
forbid_entry() {
  local pattern="$1"
  if grep -Eq "$pattern" <<<"$entries"; then
    echo "APK smoke check failed: forbidden packaged asset matched $pattern" >&2
    exit 1
  fi
}
require_matches_source() {
  local entry="$1"
  local source_rel="$2"
  local source="$SOURCE_DIR/$source_rel"
  local tmp
  require_entry "$entry"
  test -f "$source" || { echo "APK smoke check failed: source file missing: $source_rel" >&2; exit 1; }
  tmp="$(mktemp)"
  if ! unzip -p "$APK" "$entry" >"$tmp"; then
    rm -f "$tmp"
    echo "APK smoke check failed: could not extract $entry" >&2
    exit 1
  fi
  if ! cmp -s "$tmp" "$source"; then
    rm -f "$tmp"
    echo "APK smoke check failed: packaged $entry does not match source $source_rel" >&2
    exit 1
  fi
  rm -f "$tmp"
}

# Basic installable Android payload.
require_entry "AndroidManifest.xml"
require_entry "classes.dex"
require_entry "resources.arsc"

# The Android asset sync includes all current src/ and workspace-live/ files.
# Compare every one byte-for-byte, including new modules added after this builder version.
require_matches_source "assets/www/index.html" "index.html"
require_matches_source "assets/www/styles.css" "styles.css"
for directory in src workspace-live; do
  test -d "$SOURCE_DIR/$directory" || { echo "APK smoke check failed: source directory missing: $directory" >&2; exit 1; }
  while IFS= read -r -d '' source; do
    source_rel="${source#"$SOURCE_DIR/"}"
    case "$source_rel" in
      src/riftbrowser-*|*/manifest.webmanifest|*/*sw.js|*/pwa-*) continue ;;
    esac
    require_matches_source "assets/www/$source_rel" "$source_rel"
  done < <(find "$SOURCE_DIR/$directory" -type f -print0)
done

# A previously generated or unexpected www/ file must not ride along in the APK.
while IFS= read -r entry; do
  case "$entry" in
    assets/www/*)
      case "$entry" in */) continue ;; esac
      source_rel="${entry#assets/www/}"
      case "$source_rel" in
        index.html|styles.css|src/*|workspace-live/*) ;;
        *) echo "APK smoke check failed: unexpected web asset: $entry" >&2; exit 1 ;;
      esac
      test -f "$SOURCE_DIR/$source_rel" || {
        echo "APK smoke check failed: stale web asset: $entry" >&2
        exit 1
      }
      ;;
  esac
done <<< "$entries"

# Native browser-injected assets come from android/app/src/main/assets.
require_matches_source "assets/riftbrowser-mcp-app.js" "android/app/src/main/assets/riftbrowser-mcp-app.js"
require_matches_source "assets/adapters/ai-adapter-registry.js" "android/app/src/main/assets/adapters/ai-adapter-registry.js"

# These are intentionally excluded from Android. Their return means the web/PWA packaging
# boundary drifted and the APK is carrying the wrong boot model.
forbid_entry '^assets/www/manifest\.webmanifest$'
forbid_entry '^assets/www/(.*/)?sw\.js$'
forbid_entry '^assets/www/(.*/)?pwa-'

# Regression guards for architecture we deliberately retired/replaced.
if unzip -p "$APK" assets/www/styles.css | grep -q '\.rift-ai-'; then
  echo 'APK smoke check failed: retired .rift-ai-* cockpit CSS was packaged.' >&2
  exit 1
fi
if ! unzip -p "$APK" assets/www/workspace-live/index.html | grep -q 'Workspace Records'; then
  echo 'APK smoke check failed: Workspace Records UI marker is missing.' >&2
  exit 1
fi

printf 'APK smoke check passed: %s entries; critical RiftOS assets match source.\n' "$(wc -l <<<"$entries" | tr -d ' ')"
