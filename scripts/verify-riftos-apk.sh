#!/usr/bin/env bash
set -euo pipefail

APK="${1:?usage: verify-riftos-apk.sh <apk> [source-dir]}"
SOURCE_DIR="${2:-$(pwd)}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
test -f "$APK" || { echo "APK not found: $APK" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo 'unzip is required for APK smoke validation.' >&2; exit 1; }
command -v cmp >/dev/null 2>&1 || { echo 'cmp is required for APK smoke validation.' >&2; exit 1; }
AAPT2="${ANDROID_HOME:?}/build-tools/36.0.0/aapt2"
test -x "$AAPT2" || { echo "APK smoke check failed: aapt2 not found at $AAPT2" >&2; exit 1; }

entries="$(unzip -Z1 "$APK")"

duplicates="$(sort <<<"$entries" | uniq -d)"
if [ -n "$duplicates" ]; then
  echo "APK smoke check failed: duplicate ZIP entries detected:" >&2
  printf '%s\n' "$duplicates" >&2
  exit 1
fi
if grep -Eq '(^|/)\.\.(/|$)|^/' <<<"$entries"; then
  echo 'APK smoke check failed: unsafe ZIP entry path detected.' >&2
  exit 1
fi

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
require_dex_string() {
  local needle="$1"
  local label="$2"
  local entry tmp
  while IFS= read -r entry; do
    case "$entry" in
      classes*.dex)
        tmp="$(mktemp)"
        if ! unzip -p "$APK" "$entry" >"$tmp"; then
          rm -f "$tmp"
          echo "APK smoke check failed: could not extract $entry for native-code verification" >&2
          exit 1
        fi
        if grep -aFq -- "$needle" "$tmp"; then
          rm -f "$tmp"
          return 0
        fi
        rm -f "$tmp"
        ;;
    esac
  done <<< "$entries"
  echo "APK smoke check failed: compiled DEX is missing $label" >&2
  exit 1
}
forbid_dex_string() {
  local needle="$1"
  local label="$2"
  local entry tmp
  while IFS= read -r entry; do
    case "$entry" in
      classes*.dex)
        tmp="$(mktemp)"
        if ! unzip -p "$APK" "$entry" >"$tmp"; then
          rm -f "$tmp"
          echo "APK smoke check failed: could not extract $entry for retired-code verification" >&2
          exit 1
        fi
        if grep -aFq -- "$needle" "$tmp"; then
          rm -f "$tmp"
          echo "APK smoke check failed: compiled DEX still contains retired $label" >&2
          exit 1
        fi
        rm -f "$tmp"
        ;;
    esac
  done <<< "$entries"
}

# Basic installable Android payload.
require_entry "AndroidManifest.xml"
require_entry "classes.dex"
require_entry "resources.arsc"

package_name="$($AAPT2 dump packagename "$APK" | tr -d '\r\n')"
if [ "$package_name" != 'com.riftos.app' ]; then
  echo "APK smoke check failed: packaged application ID is '$package_name', expected com.riftos.app." >&2
  exit 1
fi

manifest_tree="$($AAPT2 dump xmltree "$APK" --file AndroidManifest.xml)"
manifest_sdk_lines="$(grep -E 'android:(minSdkVersion|targetSdkVersion)' <<<"$manifest_tree" || true)"
if ! grep -Eq 'android:minSdkVersion\([^)]*\)=(26|\(type 0x10\)0x1a)([[:space:]]|$)' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: packaged minSdk is not 26.' >&2
  echo 'Observed compiled-manifest SDK lines:' >&2
  printf '%s\n' "$manifest_sdk_lines" >&2
  exit 1
fi
if ! grep -Eq 'android:targetSdkVersion\([^)]*\)=(36|\(type 0x10\)0x24)([[:space:]]|$)' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: packaged targetSdk is not 36.' >&2
  echo 'Observed compiled-manifest SDK lines:' >&2
  printf '%s\n' "$manifest_sdk_lines" >&2
  exit 1
fi

badging="$($AAPT2 dump badging "$APK")"
if grep -Fq 'application-debuggable' <<<"$badging"; then
  echo 'APK smoke check failed: release APK is marked debuggable.' >&2
  exit 1
fi

# Source, VCS and signing-key material must never leak into the APK ZIP.
forbid_entry '\.(kt|java)$'
forbid_entry '(^|/)\.git/'
forbid_entry 'riftos-debug\.keystore'
forbid_entry '\.keystore$'

# Native-only RiftOS patches must be proven in the final signed artifact too, not merely in
# the checked-out source. RiftOS owns the mandatory native-source contract in
# android/app/build.gradle.kts::verifyRiftOsAndroidSources; consume that contract here so a new
# required Kotlin runtime class automatically becomes a final-APK DEX requirement without a
# second hard-coded Builder list drifting behind it. Minification is disabled, so each top-level
# class descriptor must remain in one of the APK's DEX files.
gradle_contract="$SOURCE_DIR/android/app/build.gradle.kts"
test -f "$gradle_contract" || { echo 'APK smoke check failed: RiftOS Gradle source contract is missing.' >&2; exit 1; }
mapfile -t required_native_sources < <(
  sed -nE 's/.*"(src\/main\/java\/com\/riftos\/app\/[A-Za-z0-9_]+\.kt)".*/\1/p' "$gradle_contract"
)
if [ "${#required_native_sources[@]}" -eq 0 ]; then
  echo 'APK smoke check failed: RiftOS Gradle source contract declared no mandatory native sources.' >&2
  exit 1
fi
for source_rel in "${required_native_sources[@]}"; do
  source="$SOURCE_DIR/android/app/$source_rel"
  test -f "$source" || { echo "APK smoke check failed: mandatory native source is missing: $source_rel" >&2; exit 1; }
  class_name="${source_rel##*/}"
  class_name="${class_name%.kt}"
  descriptor="Lcom/riftos/app/${class_name};"
  require_dex_string "$descriptor" "required native class $descriptor from $source_rel"
done

# RiftDevLabLocalAgent is a private top-level object inside RiftVortexLocalAgent.kt, so it is not
# represented by a standalone Gradle source filename but is still a required structured-agent
# provenance marker in the final signed APK.
require_dex_string 'Lcom/riftos/app/RiftDevLabLocalAgent;' 'structured Dev Lab local agent'

# Retired native migration classes must not survive in final DEX through stale build cache/output.
for retired in \
  RiftShellBridge RiftSystemDump AndroidWebViewBrowserEngine RiftNativeAppHost \
  RiftPreviewActivity RiftRendererCrashGuard RiftNativeDispatcher RiftTransferManifest; do
  forbid_dex_string "Lcom/riftos/app/${retired};" "native class $retired"
done

# The exact SOURCE_SHA is compiled into BuildConfig-backed runtime diagnostics and must also
# survive into DEX when the worker provides it.
if [ -n "${SOURCE_SHA:-}" ]; then
  require_dex_string "$SOURCE_SHA" "embedded RiftOS source SHA $SOURCE_SHA"
fi

# The native Android build intentionally packages only the bounded headless compiler/runtime
# assets beneath assets/www. The retired HTML/DOM shell, broad src tree and workspace-live tree
# must never return as OS execution assets.
require_matches_source "assets/www/src/riftpp-core.js" "src/riftpp-core.js"
require_matches_source "assets/www/src/riftvm.js" "src/riftvm.js"
require_matches_source "assets/www/src/semnexis-bootstrap.js" "src/semnexis-bootstrap.js"

while IFS= read -r entry; do
  case "$entry" in
    assets/www/*)
      case "$entry" in
        */) continue ;;
        assets/www/src/riftpp-core.js|assets/www/src/riftvm.js|assets/www/src/semnexis-bootstrap.js) ;;
        *) echo "APK smoke check failed: unexpected OS web asset: $entry" >&2; exit 1 ;;
      esac
      ;;
  esac
done <<< "$entries"

# Verify every explicit Android runtime asset, including RiftBrowser adapters.
# Android's asset merger does not promise to package documentation files.
native_assets="$SOURCE_DIR/android/app/src/main/assets"
test -d "$native_assets" || { echo 'APK smoke check failed: native assets directory is missing.' >&2; exit 1; }
while IFS= read -r -d '' source; do
  source_rel="${source#"$native_assets/"}"
  case "$source_rel" in *.md) continue ;; esac
  require_matches_source "assets/$source_rel" "android/app/src/main/assets/$source_rel"
done < <(find "$native_assets" -type f -print0)

# Explicit negative guards make the retired boot/runtime boundary obvious even if the generic
# unexpected-assets loop above is later edited.
forbid_entry '^assets/www/index\.html$'
forbid_entry '^assets/www/styles\.css$'
forbid_entry '^assets/www/workspace-live/'
forbid_entry '^assets/www/manifest\.webmanifest$'
forbid_entry '^assets/www/(.*/)?sw\.js$'
forbid_entry '^assets/www/(.*/)?pwa-'

printf 'APK smoke check passed: %s entries; critical RiftOS assets match source.\n' "$(wc -l <<<"$entries" | tr -d ' ')"
