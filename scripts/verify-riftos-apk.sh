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

# C0.2: no project editor package dependency is baked into the OS manifest.
for editor_package in 'com.riftpp.editor' 'com.codynex.editor'; do
  if grep -Fq "$editor_package" <<<"$manifest_tree"; then
    echo "APK smoke check failed: fixed project editor visibility resurfaced: $editor_package" >&2
    exit 1
  fi
done
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

# Generic RAPP final-artifact proof. The mandatory Kotlin descriptor loop above proves that all
# eight Gradle-owned RAPP classes survived compilation; these literal markers prove the forward
# ABI/adapter/capability semantics survived too rather than leaving only empty class shells.
for marker in \
  'pack-rapp' \
  'install-rapp' \
  'uninstall-rapp' \
  'riftos.core.package-uninstall/1' \
  'riftos.core.packages.change/1' \
  'riftos.core.app-launch/1' \
  'riftos.core.capability-consent/1' \
  'riftos.core.ui-effect/1' \
  'installed-apps' \
  'launch-rapp' \
  'rapp-list' \
  'riftos.rapp-project/1' \
  'riftos.rapp/1' \
  'riftos-app-abi/1' \
  'riftos-runtime-providers/1' \
  'riftos-runtime-exec/1' \
  'riftos-runtime-status/1' \
  'riftos.core.status/1' \
  'riftos.core.sessions/1' \
  'riftos.core.app-surfaces/1' \
  'riftos.core.input-focus/1' \
  'riftos.core.apps/1' \
  'riftos.shell.client.terminal/1' \
  'riftos.shell.client.graphical/1' \
  'riftos.core.surface-ipc/1' \
  'riftos.shell.client.remote-ipc/1' \
  'rift-core-rapp-event' \
  'eventExecutorOwner' \
  'eventQueueOwner' \
  'headlessExecution' \
  'appExecutionIndependentOfDesktop' \
  'riftos.runtime.provider/1' \
  'runtime-status' \
  'riftpp-rws2-rui3-v1' \
  'riftpp-generic-v1' \
  'Generic Rift++ response magic is invalid' \
  'RAPP pending event queue exceeded bound' \
  'RAPP Core effect chain exceeded bound' \
  'state.bin' \
  'RAPP persisted state is out of bounds' \
  'RAPP persisted state escaped program root' \
  'Installed RAPP state is not a file' \
  'setting:permissions:' \
  'fs.read' \
  'fs.write' \
  'readBytes' \
  'writeBytes' \
  'riftos-fs-bytes-read/1' \
  'riftos-fs-bytes-write/1' \
  'signing.identity' \
  'signSha256RsaPkcs1' \
  'riftos-signing-identity/1' \
  'riftbuild-apk-v2-rsa-v1' \
  'SHA256withRSA' \
  'network' \
  'clipboard.read' \
  'clipboard.write' \
  'share' \
  'build.local' \
  'window.title'; do
  require_dex_string "$marker" "generic RAPP marker $marker"
done

# Retained Rift++ compatibility/reference headless-shell proof. These strings are emitted from the native QuickJS host
# and its embedded runtime scripts, so the signed APK must retain the stateful/software command
# families plus the canonical UTF-8/unsigned-byte boundary proved by test-riftpp-shell.mjs.
for marker in \
  'riftpp-shell-self-test/3' \
  'riftpp-text-model-benchmark-v2' \
  'riftpp-semantic-compat-device-suite/1' \
  'headless-quickjs' \
  'run-stateful' \
  'exec-stateful' \
  'run-software' \
  'exec-software' \
  'state.load' \
  'state.save' \
  'state.remove' \
  'software.caseId' \
  'software.source' \
  'text-model-benchmark' \
  'semantic-compat' \
  'Only SHA-256 is available' \
  'out[i] = raw[i] & 255;' \
  'Array.from(view, value => value & 255)'; do
  require_dex_string "$marker" "Rift++ headless runtime marker $marker"
done
# The promoted generic build-provider boundary must survive into the signed DEX.
# Build recipes/packing/signing stay external; RiftOS retains only reusable execution,
# RAPP lifecycle, verification, and Android-install capabilities.
for marker in \
  'riftbuild-managed-compiler-run/1' \
  'riftbuild-kotlin-toolchain-status/2' \
  'rift-jvm-dex/1' \
  'compiler-status' \
  'compiler-run' \
  'jvm-status' \
  'jvm-dex' \
  'pack-rapp' \
  'install-rapp' \
  'uninstall-rapp' \
  'launch-rapp' \
  'rapp-list' \
  'v2 signed-data RSA signature verification failed' \
  'v2 protected APK content digest mismatch'; do
  require_dex_string "$marker" "generic post-purge RiftBuild marker $marker"
done

# Retired embedded compiler/prepared-tree/pack/sign semantics must not reappear in the APK.
for retired_marker in \
  'compile-native' \
  'riftbuild-native-object-compile-v1' \
  'extract-object-text' \
  'riftbuild-native-object-text-v1' \
  'toolchain-install-bundled' \
  'riftbuild-native-toolchain-install-v1' \
  'riftbuild/android-clang-v1.zip' \
  '%COMPILER_DIR%' \
  '%TOOLCHAIN%' \
  '%SYSROOT%' \
  'prepare-native-app' \
  'riftbuild-native-toolchain-status-v1' \
  'riftbuild-native-compile-v1' \
  'riftbuild-native-app-prepare-v3' \
  'riftbuild-native-app-validation-v2' \
  'riftbuild-runtime-profile/1' \
  'riftbuild-android-clang-toolchain/1' \
  'riftbuild-native-project/1' \
  'riftbuild-native-app/1' \
  'riftbuild-native-app/2' \
  'riftbuild-native-app/3'; do
  forbid_dex_string "$retired_marker" "retired embedded RiftBuild marker $retired_marker"
done

for retired_marker in 'riftpp-android-adapter/1' 'com.riftpp.android.RiftppActivity' 'riftpp-adapter'; do
  forbid_dex_string "$retired_marker" "retired Rift++ runtime identity $retired_marker"
done

# Persistent RiftShell jobs must survive into the signed DEX. These markers prove the new
# long-command lifecycle is packaged rather than the retired request-bound 60-second behavior.
for marker in \
  'rift.shell-job/1' \
  'rift.shell-jobs/1' \
  'cancel_requested' \
  'completed_after_cancel_request' \
  'completed_result_too_large' \
  'resubmit as a shell job' \
  'Managed JVM tool was cancelled'; do
  require_dex_string "$marker" "persistent RiftShell job marker $marker"
done

# Editor control is external software, not a built-in RiftShell command surface.
# The editor's current Binder protocol remains independently tested until its
# mirrored APK payload is removed in a separate C0 gate.
for retired_editor_shell in \
  'usage: riftpp-editor' \
  'usage: codynex-editor' \
  'riftpp-editor native-compile' \
  'riftpp-editor native-run' \
  'riftpp-editor native-preflight' \
  'riftpp-editor native-build-debug'; do
  forbid_dex_string "$retired_editor_shell" "project-specific editor shell command $retired_editor_shell"
done
# Mirrored editor Binder service markers are now forbidden by C0.2 below.

# RiftGit mode-preserving push must survive compilation into the release DEX, not only exist
# in source. These strings are emitted by the executable/symlink fallback path.
require_dex_string 'git-data-mode-preserving' 'RiftGit mode-preserving Git-data transport'
require_dex_string 'Unsupported Git blob mode' 'RiftGit guarded Git blob mode validation'
require_dex_string '.gitignore pattern exceeds' 'RiftGit bounded root .gitignore parser'

# RiftLLM qualification bridge final-artifact proof. Require the fixed frozen-B2 primer plus
# RiftPack, process-death, and RiftTrainData V2 adversarial shell aliases with their exact Provider
# method identifiers so source-only exposure cannot be mistaken for a live APK.
require_dex_string 'text-encoding-prime-b2' 'RiftLLM frozen B2 tokenizer priming shell route'
require_dex_string 'tokenizer/output/rift-token-b-balanced-v2.riftbpe' 'RiftLLM frozen B2 tokenizer fixed source path'
require_dex_string '314e3a732d4cc4c31c40c9b0add3fffcec38c8a4b40e0d228bdc4eed1addbbd1' 'RiftLLM frozen B2 tokenizer SHA-256 lock'
require_dex_string 'riftpack-qualification-start' 'RiftLLM RiftPack qualification start shell route'
require_dex_string 'riftpack-qualification-status' 'RiftLLM RiftPack qualification status shell route'
require_dex_string 'riftpack_qualification_start' 'RiftLLM RiftPack qualification start Provider method'
require_dex_string 'riftpack_qualification_status' 'RiftLLM RiftPack qualification status Provider method'
require_dex_string 'process-death-start' 'RiftLLM process-death recovery start shell route'
require_dex_string 'process-death-status' 'RiftLLM process-death recovery status shell route'
require_dex_string 'rift_micro_process_death_start' 'RiftLLM process-death recovery start Provider method'
require_dex_string 'rift_micro_process_death_status' 'RiftLLM process-death recovery status Provider method'
require_dex_string 'train-v2-adversarial-start' 'RiftLLM RiftTrainData V2 adversarial start shell route'
require_dex_string 'train-v2-adversarial-status' 'RiftLLM RiftTrainData V2 adversarial status shell route'
require_dex_string 'train_v2_adversarial_start' 'RiftLLM RiftTrainData V2 adversarial start Provider method'
require_dex_string 'train_v2_adversarial_status' 'RiftLLM RiftTrainData V2 adversarial status Provider method'
require_dex_string 'train-v2-builder-start' 'RiftLLM RiftTrainData V2 builder qualification start shell route'
require_dex_string 'train-v2-builder-status' 'RiftLLM RiftTrainData V2 builder qualification status shell route'
require_dex_string 'train_v2_builder_start' 'RiftLLM RiftTrainData V2 builder qualification start Provider method'
require_dex_string 'train_v2_builder_status' 'RiftLLM RiftTrainData V2 builder qualification status Provider method'

# C0.2 final-artifact proof: project editor implementation and its stale
# Binder protocol must NOT be part of the signed OS DEX. The independent
# project repos own these implementations; RiftOS retains the generic host.
for retired_editor_dex in \
  'Lcom/codynex/' \
  'Lcom/riftpp/editor/' \
  'Lcom/riftpp/apphost/' \
  'Lcom/riftos/app/RiftRappRiftppAdapter;' \
  'codynex-editor-bridge-compile/1' \
  'codynex-editor-bridge-preview/1' \
  'codynex-editor-bridge-native-proof/1' \
  'codynex-editor-bridge-build-apk/1' \
  'riftpp-editor-native-compile/1' \
  'riftpp-editor-native-run/1' \
  'riftpp-editor-native-preflight/1' \
  'riftpp-editor-native-build/1'; do
  forbid_dex_string "$retired_editor_dex" "embedded project editor DEX marker $retired_editor_dex"
done
for retired_marker in \
  'com.riftos.app.codynexcompiler' \
  'codynex-c0-ref/0.11.0' \
  'codynex-c0-ref/0.12.0' \
  '/workspace/Codynex/external/language/l0/compiler/c0_reference.js' \
  'codynex-c0-project-host-run/1' \
  'riftosplus-host-snapshot/1'; do
  forbid_dex_string "$retired_marker" "retired Codynex compiler authority $retired_marker"
done

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
