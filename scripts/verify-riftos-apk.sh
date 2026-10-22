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
kotlin_toolchain_prefix="assets/riftbuild/kotlin-toolchain"
require_entry "$kotlin_toolchain_prefix/android.jar"
require_entry "$kotlin_toolchain_prefix/kotlin-stdlib.jar"
require_entry "$kotlin_toolchain_prefix/toolchain.properties"
toolchain_metadata="$(unzip -p "$APK" "$kotlin_toolchain_prefix/toolchain.properties" | tr -d '\r')"
if ! grep -Fxq 'androidApiLevel=36' <<<"$toolchain_metadata"; then
  echo 'APK smoke check failed: signed SDK36 toolchain metadata is missing.' >&2
  exit 1
fi
for sha_key in androidJarSha256 kotlinStdlibSha256; do
  if [ "$(grep -Ec "^${sha_key}=[0-9a-f]{64}$" <<<"$toolchain_metadata")" -ne 1 ]; then
    echo "APK smoke check failed: invalid or missing JVM toolchain digest ${sha_key}." >&2
    exit 1
  fi
done
forbid_entry '^assets/riftbuild/managed-runtimes/riftpp-adapter-v1/classes([2-9]|[1-9][0-9]+)?\.dex$'

for toolchain_asset in \
  "$kotlin_toolchain_prefix/android.jar" \
  "$kotlin_toolchain_prefix/kotlin-stdlib.jar"; do
  toolchain_tmp="$(mktemp)"
  if ! unzip -p "$APK" "$toolchain_asset" >"$toolchain_tmp"; then
    rm -f "$toolchain_tmp"
    echo "APK smoke check failed: could not extract Kotlin toolchain asset: $toolchain_asset" >&2
    exit 1
  fi
  if [ ! -s "$toolchain_tmp" ]; then
    rm -f "$toolchain_tmp"
    echo "APK smoke check failed: Kotlin toolchain asset is empty: $toolchain_asset" >&2
    exit 1
  fi
  if ! unzip -tqq "$toolchain_tmp" >/dev/null 2>&1; then
    rm -f "$toolchain_tmp"
    echo "APK smoke check failed: Kotlin toolchain asset is not a valid JAR: $toolchain_asset" >&2
    exit 1
  fi
  case "$toolchain_asset" in
    */android.jar) toolchain_sha_key=androidJarSha256 ;;
    */kotlin-stdlib.jar) toolchain_sha_key=kotlinStdlibSha256 ;;
    *) echo 'APK smoke check failed: unrecognized JVM toolchain asset.' >&2; exit 1 ;;
  esac
  expected_sha="$(sed -n "s/^${toolchain_sha_key}=//p" <<<"$toolchain_metadata")"
  actual_sha="$(sha256sum "$toolchain_tmp" | awk '{print $1}')"
  if [ "$expected_sha" != "$actual_sha" ]; then
    rm -f "$toolchain_tmp"
    echo "APK smoke check failed: packaged JVM toolchain identity mismatch for $toolchain_asset." >&2
    exit 1
  fi
  rm -f "$toolchain_tmp"
done

compiler_seed_prefix="assets/riftbuild/compiler-seeds"
require_entry "$compiler_seed_prefix/kotlin-android-2.4.0.apk"
require_entry "$compiler_seed_prefix/manifest.txt"
compiler_seed_tmp="$(mktemp)"
if ! unzip -p "$APK" "$compiler_seed_prefix/kotlin-android-2.4.0.apk" >"$compiler_seed_tmp"; then
  rm -f "$compiler_seed_tmp"
  echo 'APK smoke check failed: could not extract managed Kotlin compiler seed APK.' >&2
  exit 1
fi
if [ ! -s "$compiler_seed_tmp" ] || ! unzip -tqq "$compiler_seed_tmp" >/dev/null 2>&1; then
  rm -f "$compiler_seed_tmp"
  echo 'APK smoke check failed: managed Kotlin compiler seed is not a valid non-empty APK/ZIP.' >&2
  exit 1
fi
if ! unzip -Z1 "$compiler_seed_tmp" | grep -Fxq 'classes.dex'; then
  rm -f "$compiler_seed_tmp"
  echo 'APK smoke check failed: managed Kotlin compiler seed has no classes.dex.' >&2
  exit 1
fi
compiler_seed_bytes="$(wc -c <"$compiler_seed_tmp" | tr -d '[:space:]')"
compiler_seed_sha="$(sha256sum "$compiler_seed_tmp" | awk '{print $1}')"
compiler_seed_manifest="$(unzip -p "$APK" "$compiler_seed_prefix/manifest.txt" | tr -d '\r')"
compiler_seed_expected="kotlin-android-2.4.0.apk=${compiler_seed_bytes}:${compiler_seed_sha}"
if ! grep -Fxq "$compiler_seed_expected" <<<"$compiler_seed_manifest"; then
  rm -f "$compiler_seed_tmp"
  echo 'APK smoke check failed: managed Kotlin compiler seed identity manifest does not match packaged APK.' >&2
  exit 1
fi
rm -f "$compiler_seed_tmp"

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

# V063 APK installer bridge must survive all the way into the SIGNED
# Android host. The independent Core still owns permission grants and
# RiftBuild Hosted still verifies its own output; this is only Android UI.
for marker in 'androidx.core.content.FileProvider' \
  'com.riftos.app.buildapks' \
  'android:grantUriPermissions' \
  'android.support.FILE_PROVIDER_PATHS'; do
  if ! grep -Fq "$marker" <<<"$manifest_tree"; then
    echo "APK smoke check failed: generic Android installer provider missing $marker." >&2
    exit 1
  fi
done
# AAPT2/AGP resource optimization renames source res/xml/*.xml entries to
# compiled names such as res/bX.xml. Resolve the logical symbol through the
# signed APK resource table, then inspect that exact compiled XML entry.
# Never accept a mere source-file check or a resource-table-only assertion.
resolver="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-apk-xml-resource.py"
test -f "$resolver" || {
  echo 'APK smoke check failed: compiled XML resolver missing.' >&2
  exit 1
}
build_apk_paths_file="$("$AAPT2" dump resources "$APK" | python3 "$resolver" xml/rift_build_apk_paths)" || {
  echo 'APK smoke check failed: cannot resolve compiled FileProvider XML resource.' >&2
  exit 1
}
require_entry "$build_apk_paths_file"
build_apk_paths_tree="$("$AAPT2" dump xmltree "$APK" --file "$build_apk_paths_file")"
for marker in 'rift-build-apks' 'riftfs/documents/builds/'; do
  if ! grep -Fq "$marker" <<<"$build_apk_paths_tree"; then
    echo "APK smoke check failed: confined APK FileProvider XML missing $marker." >&2
    exit 1
  fi
done
# DEX owners and the capability marker must be retained even if the Android
# manifest/provider survived a broken or incomplete compilation.
require_dex_string 'apk.install' "apk.install Core/Shell capability constant"
require_dex_string 'tool.invoke' "generic RAPP Core-owned tool invocation ABI constant"
require_dex_string 'Lcom/riftos/app/RiftShellPlatformServicesAdapter;' "external Shell Android installer adapter"
require_dex_string '/D:/Builds/' "Android APK installation confined to RiftFS Builds root"

# Codynex compiler authority lives in the standalone Codynex Editor. The final
# RiftOS manifest must not restore the retired provider/LR0 surfaces.
if grep -Eq 'CodynexCompilerProvider|com\.riftos\.app\.codynexcompiler|com\.codynex\.lr0lab' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: retired Codynex provider/LR0 manifest authority resurfaced.' >&2
  exit 1
fi
# C1.0: Android application bootstrap names the Core owner, never the UI shell.
if ! grep -Fq 'RiftCoreApplication' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: Core Application bootstrap missing from signed APK.' >&2
  exit 1
fi

# C0.2.5: Android must permit discovery of installed generic runtime services
# without hardcoding any particular language/runtime provider package.
if ! grep -Fq 'com.riftos.runtime.EXECUTE_V1' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: external runtime provider visibility is absent.' >&2
  exit 1
fi

# Narrow generic Android Binder tool-provider visibility is required for
# external Core v0.6.9. No broad QUERY_ALL_PACKAGES grant is necessary.
if ! grep -Fq 'com.riftos.tool.BIND_V1' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: generic Binder tool-provider visibility is absent.' >&2
  exit 1
fi

# C0.2: forbid retired Rift++ editor visibility in the signed APK.
# v0.6.4 intentionally discovers the separately installed Codynex Editor for
# user-approved Binder connections; it is NOT an embedded compiler/editor.
if grep -Fq 'com.riftpp.editor' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: retired Rift++ editor package visibility resurfaced.' >&2
  exit 1
fi
if ! grep -Fq 'com.codynex.editor' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: external Codynex Editor visibility is absent.' >&2
  exit 1
fi
for retired_riftpp_visibility in 'com.riftpp.editor.nativev1' 'com.riftpp.editor.adapterr1' 'com.riftpp.nativeproof'; do
  if grep -Fq "$retired_riftpp_visibility" <<<"$manifest_tree"; then
    echo "APK smoke check failed: Rift++ proof package visibility resurfaced in the compiled RiftOS manifest: $retired_riftpp_visibility" >&2
    exit 1
  fi
done
extract_native_line="$(grep -F 'android:extractNativeLibs' <<<"$manifest_tree" || true)"
if [ -z "$extract_native_line" ] || ! grep -Eq '(0xffffffff|true)' <<<"$extract_native_line"; then
  echo 'APK smoke check failed: compiled manifest does not retain extractNativeLibs=true for RiftBuild host compiler execution.' >&2
  printf '%s\n' "$extract_native_line" >&2
  exit 1
fi
legacy_riftpp_compiler_process="$(grep -F ':riftppCompiler' <<<"$manifest_tree" || true)"
if grep -Eq 'RiftppCompilerService|RiftppDynamicCompilerService' <<<"$manifest_tree" || [ -n "$legacy_riftpp_compiler_process" ]; then
  echo 'APK smoke check failed: Rift++-named compiler service/process resurfaced.' >&2
  printf '%s\n' "$legacy_riftpp_compiler_process" >&2
  exit 1
fi
if ! grep -Fq 'RiftNativeBufferCompilerService' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: compiled manifest is missing RiftNativeBufferCompilerService.' >&2
  exit 1
fi
if ! grep -Fq ':riftNativeBufferCompiler' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: RiftNativeBufferCompilerService is not process-isolated.' >&2
  exit 1
fi
if ! grep -Fq 'RiftManagedJvmToolService' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: compiled manifest is missing RiftManagedJvmToolService.' >&2
  exit 1
fi
if ! grep -Fq ':riftJvmToolHot' <<<"$manifest_tree"; then
  echo 'APK smoke check failed: RiftManagedJvmToolService is not isolated in :riftJvmToolHot.' >&2
  exit 1
fi

badging="$($AAPT2 dump badging "$APK")"
if grep -Fq 'application-debuggable' <<<"$badging"; then
  echo 'APK smoke check failed: release APK is marked debuggable.' >&2
  exit 1
fi

# The retired embedded Android-host clang toolchain must not survive the purge.
forbid_entry '^assets/riftbuild/android-clang-v1\.zip$'
forbid_entry '^lib/(arm64-v8a|armeabi-v7a|x86|x86_64)/lib(clang_exec|ld_lld_exec|ld_lld_shim)\.so$'

# Source, VCS and signing-key material must never leak into the APK ZIP.
forbid_entry '\.(kt|java)$'
forbid_entry '(^|/)\.git/'
forbid_entry 'riftos-debug\.keystore'
forbid_entry '\.keystore$'

# Native-only RiftOS patches must be proven in the final signed artifact too, not merely in
# the checked-out source. RiftOS owns the mandatory native-source contract in
# android/app/build.gradle.kts::verifyRiftOsAndroidSources; consume that contract here so a new
# required Kotlin source automatically becomes a final-APK DEX requirement without a
# second hard-coded Builder list drifting behind it. Package names and real column-zero top-level
# declarations are parsed from source; filenames are not treated as class names. Minification is
# disabled, so each derived top-level class descriptor must remain in one of the APK's DEX files.
gradle_contract="$SOURCE_DIR/android/app/build.gradle.kts"
test -f "$gradle_contract" || { echo 'APK smoke check failed: RiftOS Gradle source contract is missing.' >&2; exit 1; }
mapfile -t required_native_sources < <(
  sed -nE 's/.*"(src\/main\/java\/(com\/riftos\/app)\/[A-Za-z0-9_]+\.kt)".*/\1/p' "$gradle_contract"
)
if [ "${#required_native_sources[@]}" -eq 0 ]; then
  echo 'APK smoke check failed: RiftOS Gradle source contract declared no mandatory native sources.' >&2
  exit 1
fi
for source_rel in "${required_native_sources[@]}"; do
  source="$SOURCE_DIR/android/app/$source_rel"
  test -f "$source" || { echo "APK smoke check failed: mandatory native source is missing: $source_rel" >&2; exit 1; }

  source_package="$(sed -nE 's/^[[:space:]]*package[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*).*/\1/p' "$source" | head -n 1)"
  test -n "$source_package" || {
    echo "APK smoke check failed: mandatory Kotlin source has no package declaration: $source_rel" >&2
    exit 1
  }

  mapfile -t top_level_declarations < <(
    sed -nE 's/^((public|private|internal|protected|abstract|open|final|sealed|data|enum|annotation|value|fun)[[:space:]]+)*(class|object|interface)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4/p' "$source"
  )
  if [ "${#top_level_declarations[@]}" -eq 0 ]; then
    echo "APK smoke check failed: mandatory Kotlin source has no top-level class/object/interface: $source_rel" >&2
    exit 1
  fi

  descriptor_package="${source_package//./\/}"
  for declaration in "${top_level_declarations[@]}"; do
    descriptor="L${descriptor_package}/${declaration};"
    require_dex_string "$descriptor" "required native class $descriptor from $source_rel"
  done
done

# Generic JVM dependency hardening must survive source->DEX packaging.
# Unit tests are run and receipt-checked by the Builder; this is distinct
# final signed-APK proof that the runtime and exact-classpath/rollback owners ship.
for jvm_owner in RiftJvmDexService RiftJvmJarSupport RiftJvmClasspathPolicy RiftJvmDexPublication; do
  require_dex_string "Lcom/riftos/app/${jvm_owner};" "generic JVM dependency runtime ${jvm_owner}"
done
for jvm_wire_marker in 'jvmDependencyInputsVersion' 'javaResources' \
  'kotlinStdlibVersion' 'androidApiLevel' \
  'Compiler classpath contains missing, duplicate or undeclared JVM JARs'; do
  require_dex_string "$jvm_wire_marker" "generic JVM dependency capability $jvm_wire_marker"
done

# Host-focused signed-DEX gates. Kotlin top-level classes for ALL actual
# mandatory Gradle sources were proven in the loop above. The old E0/E1/C1
# embedded Core/Shell functional string and canary assertions are retired.
# Keep explicit host process, MCP, Local Agent, protected component and
# compatibility ABI owners visible in the signed APK.
for host_descriptor in \
  RiftCoreApplication RiftShellActivity \
  RiftCoreCandidateSwitch RiftShellCandidateSwitch \
  RiftProtectedComponentManifest RiftProtectedDexVerifier \
  RiftProtectedComponentInstaller RiftProtectedRevisionRecovery \
  RiftManualRecoveryActivity RiftCoreRecoverySupervisorService \
  RiftMcpServer RiftMcpRelayClient RiftMcpOperationJournal \
  RiftToolHost RiftLocalAgentBatch RiftVortexLocalAgent \
  RiftWorkspaceRecords RiftWorkspaceWatcher RiftVolumePaths \
  RiftHostExternalAppBinderV1 RiftCoreSurfaceIpcProvider \
  RiftRappCapabilityBroker; do
  require_dex_string "Lcom/riftos/app/${host_descriptor};" "APK host owner ${host_descriptor}"
done

# Exact final-DEX evidence: zero embedded Core and graphical Shell classes.
# This must inspect the SIGNED APK rather than merely trusting Gradle lists.
# RiftNativeShell itself is retained: it is the active MCP command service.
for obsolete_impl in \
  MainActivity RiftCoreRuntime RiftCoreAppSessions \
  RiftCoreAppSurfaces RiftCoreInputFocus RiftCoreAppLifecycle \
  RiftCoreAppExecutor RiftCorePackageEvents RiftCorePackageGrants \
  RiftRappManager RiftBuildPlatformTools \
  RiftNativeDesktop RiftNativeSystemApps RiftNativeWorkspaceApps \
  RiftNativeAdminApprovals RiftRappHost RiftShellRappHost \
  RiftRemoteShellUiClient RiftRappShellCapabilityClient \
  RiftRappAbsoluteView RiftBrowserAppHost RiftBrowserWindow \
  RiftAlternateGraphicalShellActivity RiftAlternateShellClient \
  RiftRemoteShellProbeActivity; do
  forbid_dex_string "Lcom/riftos/app/${obsolete_impl};" "retired embedded owner ${obsolete_impl}"
done
require_dex_string 'Lcom/riftos/app/RiftNativeShell;' 'MCP command shell remains present'

# Generic MCP event-bus and relay diagnostics must survive in the signed DEX.
# cli.* markers are intentionally preserved relay wire compatibility, not CLI execution.
for marker in 'mcp.event-bus' 'mcp.relay' 'event.created' 'cli.event.send' 'relay.ready' 'cli.replay.request' 'cli.replay.send' 'cli.ack'; do
  require_dex_string "$marker" "MCP relay debug marker $marker"
done
# Permanently retired RiftCLI must not ship native libraries in any ABI.
forbid_entry '^lib/[^/]+/libriftcli\.so$'

# Retired Codynex machine-proof hosts must not re-enter any APK ABI.
forbid_entry '^lib/[^/]+/libcodynex_mc0_host\.so$'
forbid_entry '^lib/[^/]+/libcodynex_mc1a_host\.so$'
forbid_entry '^lib/[^/]+/libcodynex_mc1b_host\.so$'
forbid_entry '^lib/[^/]+/libcodynex_m2_vm0_host\.so$'
forbid_entry '^lib/[^/]+/libcodynex_m2b_host\.so$'
forbid_entry '^lib/[^/]+/libcodynex_mc2a_host\.so$'

# Retired Rift++ App0 and legacy compiler-host libraries must not re-enter any APK ABI.
forbid_entry '^lib/[^/]+/libriftpp_app0_host\.so$'
forbid_entry '^lib/[^/]+/libriftpp_compiler_host\.so$'

# C0.2: no project editor JNI libraries may ship for any Android ABI.
forbid_entry '^lib/[^/]+/libriftpp_editor_bridge\.so$'
forbid_entry '^lib/[^/]+/libcodynex_editor_vm\.so$'

# Generic native-buffer compiler payloads execute through a separate crash-contained host.
# Both supported ARM ABIs must be packaged; x86 variants and retired Rift++ names are forbidden.
require_entry "lib/arm64-v8a/librift_native_buffer_compiler_host.so"
require_entry "lib/armeabi-v7a/librift_native_buffer_compiler_host.so"
forbid_entry '^lib/x86/librift_native_buffer_compiler_host\.so$'
forbid_entry '^lib/x86_64/librift_native_buffer_compiler_host\.so$'
forbid_entry '^lib/[^/]+/libriftpp_dynamic_compiler_host\.so$'

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

# Retired project-specific QuickJS/Rift++/Semnexis scripts no longer belong
# in the base APK. Compilers/VMs remain source-only until packaged as registered
# external tools; preserve the active generic host services and RAPP adapters.
while IFS= read -r entry; do
  case "$entry" in
    assets/www/*)
      case "$entry" in */) ;; *)
        echo "APK smoke check failed: retired in-APK language asset: $entry" >&2
        exit 1
      ;; esac
    ;;
  esac
done <<< "$entries"
for retired_language_dex in RiftHeadlessJsRuntime; do
  forbid_dex_string "Lcom/riftos/app/${retired_language_dex};" "retired APK language host $retired_language_dex"
done
for retired_proof_dex in RiftBuildInstaller RiftApkV2Verifier RiftBuildInstallActivity RiftBuildInstallReceiver; do
  forbid_dex_string "Lcom/riftos/app/${retired_proof_dex};" "retired APK build proof class $retired_proof_dex"
done

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