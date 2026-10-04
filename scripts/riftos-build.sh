#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:?usage: riftos-build.sh <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
LOG_DIR="${RUNNER_TEMP:?}/riftos-private-logs"
OUT_DIR="${RUNNER_TEMP:?}/riftos-output"
mkdir -p "$LOG_DIR" "$OUT_DIR"

for required_command in timeout node npm gradle git grep sed sha256sum python3 dpkg-deb readelf patchelf; do
  command -v "$required_command" >/dev/null 2>&1 || {
    echo "Builder runtime is missing required command: $required_command" >&2
    exit 1
  }
done
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
[ "$NODE_MAJOR" -ge 24 ] || {
  echo "Builder requires Node 24+ for the RiftOS source gate; observed $(node --version)." >&2
  exit 1
}

SOURCE_CHECK_TIMEOUT="${SOURCE_CHECK_TIMEOUT:-12m}"
RIFTBUILD_TOOLCHAIN_TIMEOUT="${RIFTBUILD_TOOLCHAIN_TIMEOUT:-10m}"
GRADLE_VALIDATE_TIMEOUT="${GRADLE_VALIDATE_TIMEOUT:-6m}"
GRADLE_BUILD_TIMEOUT="${GRADLE_BUILD_TIMEOUT:-20m}"
APK_VERIFY_TIMEOUT="${APK_VERIFY_TIMEOUT:-3m}"

# Fail before the expensive Android build if Builder-owned gates/generators are malformed.
bash -n "$SCRIPT_DIR/verify-riftos-apk.sh"
python3 -m py_compile \
  "$SCRIPT_DIR/prepare-riftbuild-toolchain.py" \
  "$SCRIPT_DIR/test-prepare-riftbuild-toolchain.py"
python3 "$SCRIPT_DIR/test-prepare-riftbuild-toolchain.py"

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

# Builder-owned syntax preflight for the source-gate entrypoints. This runs before the
# source-owned validator so a malformed validator cannot hide its own parse failure.
for source_gate_script in   scripts/validate-rift-wiring.mjs   scripts/validate-rift-transport.mjs   scripts/validate-rift-docs.mjs   scripts/test-rift-cli-push-channel.mjs   scripts/test-rift-cli-batch-v2.mjs   scripts/test-rift-local-agent-batch.mjs   scripts/test-rift-mcp-operation-journal.mjs   scripts/test-rift-debug-hub.mjs   scripts/test-riftbuild-native.mjs   scripts/test-rift-shell-bridge.mjs   scripts/test-riftllm-bridge.mjs   scripts/test-semnexis-bootstrap.mjs   scripts/test-semnexis-arm32-exec.mjs   scripts/test-semnexis-shell.mjs; do
  node --check "$source_gate_script" >>"$LOG_DIR/source-syntax.log" 2>&1 || {
    echo "RiftOS source-gate syntax failed: $source_gate_script" >&2
    exit 1
  }
done

node -e '
  const pkg = require("./package.json");
  const check = String(pkg.scripts?.check || "");
  const transport = String(pkg.scripts?.["check:transport"] || "");
  if (!check.includes("npm run check:transport")) {
    console.error("Builder contract is stale: npm check no longer delegates to check:transport");
    process.exit(1);
  }
  for (const required of [
    "node scripts/validate-rift-wiring.mjs",
    "node scripts/validate-rift-transport.mjs",
    "node scripts/validate-rift-docs.mjs",
    "node scripts/test-rift-cli-push-channel.mjs",
    "node scripts/test-rift-cli-batch-v2.mjs",
    "node scripts/test-rift-local-agent-batch.mjs",
    "node scripts/test-rift-mcp-operation-journal.mjs",
    "node scripts/test-rift-debug-hub.mjs",
    "node scripts/test-riftbuild-native.mjs",
    "node scripts/test-rift-shell-bridge.mjs",
    "node scripts/test-riftllm-bridge.mjs",
    "node scripts/test-semnexis-bootstrap.mjs",
    "node scripts/test-semnexis-arm32-exec.mjs",
    "node scripts/test-semnexis-shell.mjs",
  ]) {
    if (!transport.includes(required)) {
      console.error("Builder contract is stale: check:transport missing " + required);
      process.exit(1);
    }
  }
'


# Semnexis self-hosting source contract. Product semantics remain owned by RiftOS,
# but Builder must fail early if the promoted source fixtures or gate wiring disappear.
semnexis_bootstrap_gate="scripts/test-semnexis-bootstrap.mjs"
semnexis_arm_gate="scripts/test-semnexis-arm32-exec.mjs"
test -f "$semnexis_bootstrap_gate" || {
  echo "Builder Semnexis contract is missing bootstrap gate: $semnexis_bootstrap_gate" >&2
  exit 1
}
grep -Fq 'ARM32 runtime must accept more than 256 functions when real artifact bounds are satisfied' "$semnexis_bootstrap_gate" || {
  echo "Builder Semnexis contract is stale: >256-function ARM32 regression marker is missing" >&2
  exit 1
}
for semnexis_fixture in \
  scripts/fixtures/semnexis-selfhost-frontend-v18.snx \
  scripts/fixtures/semnexis-selfhost-semantic-v19.snx \
  scripts/fixtures/semnexis-selfhost-native-ir-v25.snx; do
  test -f "$semnexis_fixture" || {
    echo "Builder Semnexis contract is missing promoted fixture: $semnexis_fixture" >&2
    exit 1
  }
  grep -Fq "${semnexis_fixture#scripts/fixtures/}" "$semnexis_arm_gate" || {
    echo "Builder Semnexis contract is stale: ARM32 gate no longer references $semnexis_fixture" >&2
    exit 1
  }
done
for semnexis_contract_marker in \
  'self-host v25 graph topology parity' \
  'self-host v25 graph verifier acceptance' \
  'self-host v25 execution-plan parity' \
  'self-host v25 IR function parity' \
  'self-host v25 IR parameter parity' \
  'self-host v25 IR instruction parity'; do
  grep -Fq "$semnexis_contract_marker" "$semnexis_arm_gate" || {
    echo "Builder Semnexis v25 contract marker missing: $semnexis_contract_marker" >&2
    exit 1
  }
done

# Validate the Builder's DEX-verifier assumption against the exact source contract before
# source tests/Gradle: every mandatory Kotlin source must expose a package plus at least one
# real column-zero top-level class/object/interface. Final DEX verification derives descriptors
# from those declarations rather than assuming a Kotlin filename equals a class name.
root_gradle_contract="android/build.gradle.kts"
settings_gradle_contract="android/settings.gradle.kts"
gradle_contract="android/app/build.gradle.kts"
grep -Fq 'org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.10' "$root_gradle_contract" || {
  echo 'Builder contract is stale: RiftOS root Gradle must pin Kotlin Gradle plugin 2.4.10 for QuickJS 1.0.14 metadata compatibility.' >&2
  exit 1
}
grep -Fq 'maven("https://jitpack.io")' "$settings_gradle_contract" || {
  echo 'Builder contract is stale: managed compiler payload repository is missing from Android settings.' >&2
  exit 1
}
grep -Fq 'include(":rift-managed-kotlin-tool")' "$settings_gradle_contract" || {
  echo 'Builder contract is stale: managed Kotlin compiler payload module is not included.' >&2
  exit 1
}
managed_kotlin_gradle="android/rift-managed-kotlin-tool/build.gradle.kts"
managed_kotlin_source="android/rift-managed-kotlin-tool/src/main/java/com/riftbuild/tools/kotlinc/KotlinCompilerTool.kt"
test -f "$managed_kotlin_gradle" || {
  echo 'Builder contract is stale: managed Kotlin compiler payload Gradle file is missing.' >&2
  exit 1
}
test -f "$managed_kotlin_source" || {
  echo 'Builder contract is stale: managed Kotlin compiler adapter source is missing.' >&2
  exit 1
}
grep -Fq 'com.github.PranavPurwar:kotlinc-android:2.4.0' "$managed_kotlin_gradle" || {
  echo 'Builder contract is stale: Android-compatible Kotlin compiler payload dependency is not pinned.' >&2
  exit 1
}
grep -Fq 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0' "$managed_kotlin_gradle" || {
  echo 'Builder contract is stale: managed Kotlin compiler payload is missing its coroutines runtime.' >&2
  exit 1
}
grep -Fq 'object KotlinCompilerTool' "$managed_kotlin_source" || {
  echo 'Builder contract is stale: managed Kotlin compiler JSON adapter is missing.' >&2
  exit 1
}
if grep -Fq 'kotlin-compiler-embeddable:2.4.10' "$gradle_contract"; then
  echo 'Builder contract is stale: RiftOS app must not embed the desktop Kotlin compiler implementation.' >&2
  exit 1
fi
for required_gradle_contract in \
  'namespace = "com.riftos.app"' \
  'applicationId = "com.riftos.app"' \
  'compileSdk = 36' \
  'minSdk = 26' \
  'targetSdk = 36' \
  'JavaVersion.VERSION_17' \
  'getByName("release") { isMinifyEnabled = false }' \
  'ndkVersion = "28.2.13676358"' \
  'abiFilters += listOf("arm64-v8a", "armeabi-v7a")' \
  'path = file("src/main/cpp/CMakeLists.txt")' \
  'version = "3.22.1"' \
  'io.github.dokar3:quickjs-kt:1.0.14' \
  'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0' \
  'com.android.tools:r8:8.13.23'; do
  grep -Fq "$required_gradle_contract" "$gradle_contract" || {
    echo "Builder contract is stale: expected Gradle contract missing: $required_gradle_contract" >&2
    exit 1
  }
done
mapfile -t required_native_sources < <(
  sed -nE 's/.*"(src\/main\/java\/(com\/riftos\/app|com\/riftpp\/editor|com\/riftpp\/apphost)\/[A-Za-z0-9_]+\.kt)".*/\1/p' "$gradle_contract"
)
test "${#required_native_sources[@]}" -gt 0 || { echo 'Builder contract preflight found no mandatory Kotlin sources.' >&2; exit 1; }
for source_rel in "${required_native_sources[@]}"; do
  source="android/app/$source_rel"
  test -f "$source" || { echo "Builder contract preflight missing mandatory Kotlin source: $source_rel" >&2; exit 1; }

  source_package="$(sed -nE 's/^[[:space:]]*package[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*).*/\1/p' "$source" | head -n 1)"
  test -n "$source_package" || {
    echo "Builder Kotlin declaration preflight found no package declaration: $source_rel" >&2
    exit 1
  }

  mapfile -t top_level_declarations < <(
    sed -nE 's/^((public|private|internal|protected|abstract|open|final|sealed|data|enum|annotation|value|fun)[[:space:]]+)*(class|object|interface)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4/p' "$source"
  )
  test "${#top_level_declarations[@]}" -gt 0 || {
    echo "Builder Kotlin declaration preflight found no top-level class/object/interface: $source_rel" >&2
    exit 1
  }
done

# RiftGit mode-preserving push contract. Ordinary 100644 changes may keep the single-request
# GraphQL fast path, but modified executable blobs must fall back to Git-data objects
# so tracked Git modes survive the commit.
riftgit_source="android/app/src/main/java/com/riftos/app/RiftNativeGit.kt"
test -f "$riftgit_source" || {
  echo 'Builder RiftGit contract is missing RiftNativeGit.kt.' >&2
  exit 1
}
for required_riftgit_contract in \
  'needsModePreservingTransport' \
  'atomicPushGitData(' \
  'checkedBlobMode(' \
  '"git-data-mode-preserving"' \
  'mode == "100755"' \
  '.put("force", false)' \
  '"graphql-createCommitOnBranch"' \
  'MAX_GITIGNORE_BYTES = 256L * 1024L' \
  'MAX_GITIGNORE_RULES = 4096' \
  'gitIgnoreRules(repoRoot)' \
  'gitIgnored(relative, ignoreRules)' \
  'ignoredByRules(parent)' \
  'isTracked || !gitIgnored'; do
  grep -Fq "$required_riftgit_contract" "$riftgit_source" || {
    echo "Builder RiftGit mode-preserving contract missing: $required_riftgit_contract" >&2
    exit 1
  }
done
if grep -Fq 'Single-request GitHub push cannot safely preserve mode' "$riftgit_source"; then
  echo 'Builder RiftGit contract regressed to the old 100644-only push rejection.' >&2
  exit 1
fi
# Codynex Editor is the only live Codynex authority reachable from RiftOS.
# RiftOS owns bounded Binder transport plus the mirrored editor/runtime payload contract;
# it must not regain compiler generations, C0/LR0 providers, or special RiftBuild prepare routes.
manifest_contract="android/app/src/main/AndroidManifest.xml"
editor_activity="android/app/src/main/java/com/codynex/editorapp/MainActivity.kt"
editor_toolchain="android/app/src/main/java/com/codynex/editorapp/CodynexEditorToolchainPort.kt"
editor_compiler_runtime="android/app/src/main/java/com/codynex/editorapp/CodynexCompilerRuntime.kt"
editor_bridge_service="android/app/src/main/java/com/codynex/editorapp/CodynexEditorBridgeService.kt"
editor_bridge_client="android/app/src/main/java/com/riftos/app/RiftCodynexEditorBridgeClient.kt"
native_shell="android/app/src/main/java/com/riftos/app/RiftNativeShell.kt"
editor_bootstrap="android/app/src/main/java/com/codynex/editorapp/BootstrapArtifacts.kt"
editor_vm_bridge_kt="android/app/src/main/java/com/codynex/editorapp/CodynexRuntimeBridge.kt"
editor_vm_bridge_cpp="android/app/src/main/cpp/editor/editor_vm_bridge.cpp"
riftbuild_source="android/app/src/main/java/com/riftos/app/RiftBuildLocalExecutor.kt"
riftbuild_toolchain_source="android/app/src/main/java/com/riftos/app/RiftBuildNativeToolchain.kt"
riftbuild_native_app_source="android/app/src/main/java/com/riftos/app/RiftBuildNativeApp.kt"
riftbuild_installer_source="android/app/src/main/java/com/riftos/app/RiftBuildInstaller.kt"

for editor_contract_file in \
  "$manifest_contract" \
  "$editor_activity" \
  "$editor_toolchain" \
  "$editor_compiler_runtime" \
  "$editor_bridge_service" \
  "$editor_bridge_client" \
  "$native_shell" \
  "$editor_bootstrap" \
  "$editor_vm_bridge_kt" \
  "$editor_vm_bridge_cpp" \
  "$riftbuild_source" \
  "$riftbuild_toolchain_source" \
  "$riftbuild_native_app_source"; do
  test -f "$editor_contract_file" || {
    echo "Builder Codynex editor contract is missing: $editor_contract_file" >&2
    exit 1
  }
done

for retired_codynex_source in \
  android/app/src/main/java/com/riftos/app/CodynexCompilerProvider.kt \
  android/app/src/main/java/com/riftos/app/RiftCodynexBridgeClient.kt \
  android/app/src/main/java/com/codynex/editorapp/Source0SelfHostToolchainPort.kt; do
  if test -e "$retired_codynex_source"; then
    echo "Builder contract failed: retired Codynex authority resurfaced: $retired_codynex_source" >&2
    exit 1
  fi
done

if grep -Eq 'CodynexCompilerProvider|com\.riftos\.app\.codynexcompiler|com\.codynex\.lr0lab' "$manifest_contract"; then
  echo 'Builder contract failed: retired Codynex provider/LR0 manifest authority resurfaced.' >&2
  exit 1
fi
if grep -Eq 'prepare-codynex-|compileCodynexC0|codynex-c0-ref|c0_reference\.js' "$riftbuild_source"; then
  echo 'Builder contract failed: retired Codynex compiler/proof RiftBuild authority resurfaced.' >&2
  exit 1
fi

for required_gradle_editor_source in \
  '"src/main/java/com/riftos/app/RiftCodynexEditorBridgeClient.kt"' \
  '"src/main/java/com/codynex/editorapp/CodynexCompilerRuntime.kt"' \
  '"src/main/java/com/codynex/editorapp/CodynexEditorToolchainPort.kt"' \
  '"src/main/java/com/codynex/editorapp/CodynexEditorBridgeService.kt"'; do
  grep -Fq "$required_gradle_editor_source" "$gradle_contract" || {
    echo "Builder current Codynex editor source contract missing: $required_gradle_editor_source" >&2
    exit 1
  }
done
if grep -Eq 'CodynexCompilerProvider\.kt|validateCodynexCompilerTransition|Source0SelfHostToolchainPort\.kt' "$gradle_contract"; then
  echo 'Builder Gradle contract still contains retired Codynex compiler authority.' >&2
  exit 1
fi

for required_editor_bridge_client in \
  'class RiftCodynexEditorBridgeClient' \
  'EDITOR_PACKAGE = "com.codynex.editor"' \
  'com.codynex.editorapp.CodynexEditorBridgeService' \
  'DESCRIPTOR = "com.codynex.editor.bridge.v1"' \
  'MAX_TREE_ENTRIES = 4096' \
  'MAX_TREE_DEPTH = 32' \
  'fun pushDirectory' \
  'fun pullDirectory'; do
  grep -Fq "$required_editor_bridge_client" "$editor_bridge_client" || {
    echo "Builder Codynex editor bridge client contract missing: $required_editor_bridge_client" >&2
    exit 1
  }
done

for required_editor_bridge_service in \
  'class CodynexEditorBridgeService' \
  'DESCRIPTOR = "com.codynex.editor.bridge.v1"' \
  'RIFTOS_PACKAGE = "com.riftos.app"' \
  '.put("folderTransport", true)' \
  '"codynex-editor-bridge-compile/1"' \
  '"codynex-editor-bridge-preview/1"' \
  '"codynex-editor-bridge-native-proof/1"' \
  '"codynex-editor-bridge-build-apk/1"' \
  'compileFresh(entry)' \
  'CodynexApkBuilder(this).build'; do
  grep -Fq "$required_editor_bridge_service" "$editor_bridge_service" || {
    echo "Builder Codynex editor bridge service contract missing: $required_editor_bridge_service" >&2
    exit 1
  }
done

for required_editor_shell_contract in \
  '"codynex-editor" -> executeCodynexEditorCommand(cwd, args)' \
  '"push-dir" -> {' \
  '"pull-dir" -> {' \
  '"compile" -> {' \
  '"preview" -> {' \
  '"native-proof" -> {' \
  '"build-apk" -> {'; do
  grep -Fq "$required_editor_shell_contract" "$native_shell" || {
    echo "Builder Codynex editor shell transport missing: $required_editor_shell_contract" >&2
    exit 1
  }
done
if grep -Eq '"codynex"[[:space:]]*->|RiftCodynexBridgeClient|codynexBridge\(' "$native_shell"; then
  echo 'Builder contract failed: retired Codynex LR0 shell route resurfaced.' >&2
  exit 1
fi

for required_editor_toolchain in \
  'class CodynexEditorToolchainPort' \
  'CodynexCompilerRuntime(context.applicationContext).compile' \
  'EditorVmTarget.VM2' \
  'CodynexRuntimeBridge.run' \
  'MAX_SOURCE_BYTES = 256 * 1024' \
  'MAX_PROJECT_BYTES = 1024 * 1024' \
  'MAX_PROJECT_MODULES = 64' \
  'MAX_CANDIDATE_BYTES = 64 * 1024'; do
  grep -Fq "$required_editor_toolchain" "$editor_toolchain" || {
    echo "Builder Codynex editor toolchain contract missing: $required_editor_toolchain" >&2
    exit 1
  }
done
if grep -Eq 'contentResolver\.call|com\.riftos\.app\.codynexcompiler|COMPILE_METHOD_VM' "$editor_toolchain"; then
  echo 'Builder Codynex editor toolchain regressed to RiftOS provider authority.' >&2
  exit 1
fi

for required_editor_compiler_runtime in \
  'class CodynexCompilerRuntime' \
  'HOT_COMPILER_WORKSPACE_PATH' \
  '.codynex/toolchains/compiler.js' \
  'BUNDLED_COMPILER_ASSET' \
  'codynex_compiler.js' \
  'quickJs {' \
  'globalThis.CodynexC0' \
  'compiler.compileProjectVM2' \
  'compiler.compileProject'; do
  grep -Fq "$required_editor_compiler_runtime" "$editor_compiler_runtime" || {
    echo "Builder Codynex editor compiler runtime contract missing: $required_editor_compiler_runtime" >&2
    exit 1
  }
done
if grep -Eq 'codynex-c0-ref/0\.11\.0|codynex-c0-ref/0\.12\.0' "$editor_compiler_runtime"; then
  echo 'Builder Codynex editor compiler host must remain compiler-version agnostic.' >&2
  exit 1
fi
for required_riftbuild_native_contract in \
  '"toolchain-status" -> nativeToolchain.status()' \
  '"toolchain-install-bundled" -> nativeToolchain.installBundled()' \
  '"compile-native" -> compileNative(' \
  '"compile-object" -> compileObject(' \
  '"extract-object-text" -> extractObjectText(' \
  '"prepare-native-app" -> prepareNativeApp(' \
  'structuredCompilerProcessExecution' \
  'downloadedToolchainsAllowed'; do
  grep -Fq "$required_riftbuild_native_contract" "$riftbuild_source" || {
    echo "Builder RiftBuild Native Compile V1 controller contract missing: $required_riftbuild_native_contract" >&2
    exit 1
  }
done
for required_riftbuild_toolchain_contract in \
  'class RiftBuildNativeToolchain' \
  'riftbuild-android-clang-toolchain/1' \
  'riftbuild-native-project/1' \
  'riftbuild-native-project-validation-v1' \
  'fun validateProject(projectRoot: File)' \
  'fun compileAssemblyObject(projectRoot: File, sourcePath: String, target: String)' \
  'riftbuild-native-object-compile-v1' \
  'Assembly object source must end in .S or .s' \
  'argv += "-c"' \
  'verifyRelocatableObject(output, abi.abi)' \
  'build/riftbuild/objects/' \
  'fun extractRelocationFreeText(projectRoot: File, objectPath: String, target: String)' \
  'riftbuild-native-object-text-v1' \
  'Native object contains relocation sections; raw text extraction is forbidden' \
  'Native object must contain exactly one .text section' \
  'build/riftbuild/blobs/' \
  'ProcessBuilder(argv)' \
  'structured-argv' \
  'downloadedToolchainsAllowed' \
  'MAX_TOOLCHAIN_ARGS = 128' \
  'MAX_LIBRARIES = 64' \
  'BUNDLED_TOOLCHAIN_ASSET = "riftbuild/android-clang-v1.zip"' \
  'riftbuild-native-toolchain-install-v1' \
  'ZipInputStream' \
  'LD_LIBRARY_PATH' \
  '.replace("%TOOLCHAIN%", toolchainRoot.absolutePath)' \
  '.replace("%SYSROOT%", sysroot.absolutePath)' \
  '.replace("%COMPILER_DIR%", compiler.parentFile?.absolutePath.orEmpty())' \
  'verifyElf'; do
  grep -Fq "$required_riftbuild_toolchain_contract" "$riftbuild_toolchain_source" || {
    echo "Builder RiftBuild Native Compile V1 toolchain contract missing: $required_riftbuild_toolchain_contract" >&2
    exit 1
  }
done
if grep -Fq '/system/bin/sh' "$riftbuild_toolchain_source"; then
  echo 'Builder RiftBuild Native Compile V1 contract regressed to shell-string execution.' >&2
  exit 1
fi
for required_riftbuild_native_app_contract in \
  'class RiftBuildNativeApp' \
  'riftbuild-native-app/1' \
  'riftbuild-native-app/2' \
  'riftbuild-native-app/3' \
  'riftbuild-runtime-profile/1' \
  'riftbuild-native-app-prepare-v3' \
  'riftbuild-native-app-validation-v2' \
  'fun validateProject(projectRoot: File)' \
  'readRuntimeProfile' \
  'materializeRuntimeProfile' \
  'MAX_RUNTIME_DEX_FILES = 8' \
  'MAX_RUNTIME_DEX_BYTES = 16L * 1024L * 1024L' \
  'runtimeProfile' \
  'activityClass' \
  'hasCode' \
  'dexDir' \
  'android.app.NativeActivity' \
  'android.app.lib_name' \
  'build/riftbuild/prepared/AndroidManifest.xml' \
  'Native app assetsDir must not point inside build/riftbuild'; do
  grep -Fq "$required_riftbuild_native_app_contract" "$riftbuild_native_app_source" || {
    echo "Builder RiftBuild generic native-app contract missing: $required_riftbuild_native_app_contract" >&2
    exit 1
  }
done
if grep -Eq 'RIFTPP_ADAPTER|riftpp-adapter|riftpp-android-adapter|com\.riftpp\.android\.RiftppActivity|materializeManagedRuntime' "$riftbuild_native_app_source"; then
  echo 'Builder contract failed: generic runtime/profile materializer regained Rift++ identity.' >&2
  exit 1
fi
for required_riftbuild_installer_contract in \
  'class RiftBuildInstaller' \
  'SAFE_PACKAGE_NAME' \
  'requireSafePackageName' \
  'Intent(Intent.ACTION_MAIN)' \
  'Intent.CATEGORY_LAUNCHER' \
  '.setPackage(safePackageName)' \
  'launch package is not bound to the latest verified install' \
  'PackageInstaller reported an unexpected package identity' \
  'USER_ACTION_REQUIRED'; do
  grep -Fq "$required_riftbuild_installer_contract" "$riftbuild_installer_source" || {
    echo "Builder RiftBuild generic installer contract missing: $required_riftbuild_installer_contract" >&2
    exit 1
  }
done
if grep -Eq 'ALLOWED_PROOF_PACKAGES|RIFTPP_[A-Z0-9_]*TARGET_PACKAGE|TARGET_PACKAGE = "com\.riftpp|EDITOR_TARGET_PACKAGE = "com\.codynex|com\.riftpp\.editor\.adapterr1' "$riftbuild_installer_source"; then
  echo 'Builder contract failed: generic RiftBuild installer regained project package identity.' >&2
  exit 1
fi
if ! grep -Fq '<package android:name="com.riftpp.editor" />' "$manifest_contract"; then
  echo 'Builder contract failed: Rift++ editor bridge package visibility is missing.' >&2
  exit 1
fi
if grep -Eq '<package android:name="com\.riftpp\.(editor\.(nativev1|adapterr1)|nativeproof)"' "$manifest_contract"; then
  echo 'Builder contract failed: RiftOS manifest regained Rift++ proof package visibility for generic install/launch.' >&2
  exit 1
fi
for required_riftbuild_gradle_source in \
  '"src/main/java/com/riftos/app/RiftBuildNativeToolchain.kt"' \
  '"src/main/java/com/riftos/app/RiftBuildNativeApp.kt"' \
  '"src/main/java/com/riftos/app/RiftBuildKotlinCompiler.kt"' \
  '"src/main/java/com/riftos/app/RiftBuildManagedToolchains.kt"' \
  '"src/main/java/com/riftos/app/RiftManagedJvmToolService.kt"' \
  '"src/main/java/com/riftos/app/RiftNativeBufferCompilerService.kt"' \
  'sourceSets["main"].jniLibs.directories.add("build/generated/riftosJniLibs")' \
  'syncRiftBuildKotlinToolchain' \
  'generated/riftosAssets/riftbuild/kotlin-toolchain' \
  'dependsOn(syncRiftBuildKotlinToolchain)' \
  'syncRiftBuildCompilerSeeds' \
  'generated/riftosAssets/riftbuild/compiler-seeds' \
  'kotlin-android-2.4.0.apk' \
  'dependsOn(syncRiftBuildCompilerSeeds)' \
  'isTransitive = false' \
  'jniLibs.useLegacyPackaging = true'; do
  grep -Fq "$required_riftbuild_gradle_source" "$gradle_contract" || {
    echo "Builder contract is stale: RiftBuild native source is not mandatory in verifyRiftOsAndroidSources: $required_riftbuild_gradle_source" >&2
    exit 1
  }
done
if grep -Fq 'syncRiftBuildRiftppAdapterRuntime' "$gradle_contract"; then
  echo 'Builder contract failed: project-specific Rift++ adapter runtime sync resurfaced in RiftOS Gradle.' >&2
  exit 1
fi

# Rift++ single-editor native-output contract. The permanent Kotlin-hosted Rift++ editor
# owns these generic compile/run/preflight/APK capabilities; they do not imply a second
# native editor or a future replacement editor.
riftpp_editor_service="android/app/src/main/java/com/riftpp/editor/RiftppEditorBridgeService.kt"
riftpp_editor_pipeline="android/app/src/main/java/com/riftpp/editor/RiftppPipeline.kt"
riftpp_editor_hex="android/app/src/main/java/com/riftpp/editor/HexAssets.kt"
riftpp_editor_apk_builder="android/app/src/main/java/com/riftpp/editor/RiftppApkBuilder.kt"
riftpp_editor_elf_preflight="android/app/src/main/java/com/riftpp/editor/RiftppNativeElfPreflight.kt"
riftpp_editor_shell="android/app/src/main/java/com/riftos/app/RiftNativeShell.kt"

for riftpp_editor_file in   "$riftpp_editor_service"   "$riftpp_editor_pipeline"   "$riftpp_editor_hex"   "$riftpp_editor_apk_builder"   "$riftpp_editor_elf_preflight"   "$riftpp_editor_shell"; do
  test -f "$riftpp_editor_file" || {
    echo "Builder Rift++ single-editor payload contract is missing: $riftpp_editor_file" >&2
    exit 1
  }
done

for required_riftpp_editor_service_contract in   '"native-compile" ->'   '"native-run" ->'   '"native-preflight" ->'   '"native-build-debug" ->'   'requiredSymbol'   'riftpp-editor-native-compile/1'   'riftpp-editor-native-run/1'   'riftpp-editor-native-preflight/1'   'riftpp-editor-native-build/1'; do
  grep -Fq "$required_riftpp_editor_service_contract" "$riftpp_editor_service" || {
    echo "Builder Rift++ editor native-output bridge contract missing: $required_riftpp_editor_service_contract" >&2
    exit 1
  }
done

for required_riftpp_editor_pipeline_contract in   'compileRecordHex('   'compileRecordSource('   'runNativeProgram('   'bootstrapCompilerForDevelopment()'; do
  grep -Fq "$required_riftpp_editor_pipeline_contract" "$riftpp_editor_pipeline" || {
    echo "Builder Rift++ editor pipeline contract missing: $required_riftpp_editor_pipeline_contract" >&2
    exit 1
  }
done

for required_riftpp_editor_hex_contract in   'decodeContinuousHex('   'decodeLineHex('; do
  grep -Fq "$required_riftpp_editor_hex_contract" "$riftpp_editor_hex" || {
    echo "Builder Rift++ editor hex contract missing: $required_riftpp_editor_hex_contract" >&2
    exit 1
  }
done

for required_riftpp_editor_apk_contract in   'fun buildNativeDebug('   'android.app.NativeActivity'   'android.app.lib_name'   'nativeLibraryName ='   'riftpp-editor-native-apk-v1'; do
  grep -Fq "$required_riftpp_editor_apk_contract" "$riftpp_editor_apk_builder" || {
    echo "Builder Rift++ editor native-output APK contract missing: $required_riftpp_editor_apk_contract" >&2
    exit 1
  }
done

for required_riftpp_editor_elf_contract in   'EM_ARM = 40'   'PT_LOAD'   'section-header table'   'writable and executable'   'PT_LOAD virtual ranges overlap'; do
  grep -Fq "$required_riftpp_editor_elf_contract" "$riftpp_editor_elf_preflight" || {
    echo "Builder Rift++ editor ELF preflight contract missing: $required_riftpp_editor_elf_contract" >&2
    exit 1
  }
done

for required_riftpp_editor_shell_contract in   'riftpp-editor native-compile'   'riftpp-editor native-run'   'riftpp-editor native-preflight'   '[required-symbol]'   'riftpp-editor native-build-debug'; do
  grep -Fq "$required_riftpp_editor_shell_contract" "$riftpp_editor_shell" || {
    echo "Builder Rift++ editor native-output shell transport contract missing: $required_riftpp_editor_shell_contract" >&2
    exit 1
  }
done

grep -Fq '"src/main/java/com/riftpp/editor/RiftppNativeElfPreflight.kt"' "$gradle_contract" || {
  echo 'Builder contract is stale: RiftppNativeElfPreflight.kt is not mandatory in verifyRiftppEditorPayload.' >&2
  exit 1
}
if grep -Fq 'prepare-codynex-' "$riftbuild_source"; then
  echo 'Builder contract failed: retired Codynex special-case RiftBuild prepare route resurfaced.' >&2
  exit 1
fi

grep -Fq 'android:extractNativeLibs="true"' "$manifest_contract" || {
  echo 'Builder RiftBuild bundled toolchain contract requires android:extractNativeLibs=true.' >&2
  exit 1
}

if grep -Eq 'compilerA|selfhost_compiler|compiler\.cx0|Fixed-point preview' \
    "$editor_activity" "$editor_toolchain" "$editor_bootstrap"; then
  echo 'Builder Codynex editor contract regressed to the obsolete MC2-A/Source0 active path.' >&2
  exit 1
fi

# Required native subsystems must remain real C++ builds, not Kotlin-only placeholders.
for native_source in \
  android/app/src/main/cpp/CMakeLists.txt \
  android/app/src/main/cpp/riftcli/rift_cli_core.cpp \
  android/app/src/main/cpp/riftcli/rift_cli_core.h \
  android/app/src/main/cpp/riftcli/rift_cli_jni.cpp \
  android/app/src/main/cpp/compiler/rift_native_buffer_compiler_host.cpp \
  android/app/src/main/cpp/editor/editor_vm_bridge.cpp \
  android/app/src/main/java/com/riftos/app/RiftCliHost.kt; do
  test -f "$native_source" || {
    echo "Builder contract preflight missing required native source: $native_source" >&2
    exit 1
  }
done
grep -Fq 'add_library(' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: RiftCLI CMake must declare a native library.' >&2
  exit 1
}
grep -Fq 'riftcli' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: RiftCLI CMake must build libriftcli.' >&2
  exit 1
}
for retired_codynex_native in \
  codynex_mc0_host \
  codynex_mc1a_host \
  codynex_mc1b_host \
  codynex_m2_vm0_host \
  codynex_m2b_host \
  codynex_mc2a_host; do
  if grep -Fq "$retired_codynex_native" android/app/src/main/cpp/CMakeLists.txt; then
    echo "Builder contract failed: retired Codynex proof target resurfaced: $retired_codynex_native" >&2
    exit 1
  fi
done
grep -Fq 'codynex_editor_vm' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libcodynex_editor_vm for Codynex editor Preview packaging.' >&2
  exit 1
}
for retired_riftpp_native in riftpp_app0_host riftpp_compiler_host; do
  if grep -Fq "$retired_riftpp_native" android/app/src/main/cpp/CMakeLists.txt; then
    echo "Builder contract is stale: retired Rift++ native target resurfaced: $retired_riftpp_native" >&2
    exit 1
  fi
done
for retired_riftpp_source in \
  android/app/src/main/cpp/riftpp/riftpp_app0_host.cpp \
  android/app/src/main/cpp/riftpp/riftpp_compiler_host.cpp \
  android/app/src/main/cpp/riftpp/riftpp_dynamic_compiler_host.cpp \
  android/app/src/main/java/com/riftos/app/RiftppCompilerService.kt \
  android/app/src/main/java/com/riftos/app/RiftppDynamicCompilerService.kt \
  android/riftpp-adapter-runtime-bundle; do
  if test -e "$retired_riftpp_source"; then
    echo "Builder contract is stale: retired Rift++ compiler source resurfaced: $retired_riftpp_source" >&2
    exit 1
  fi
done
grep -Fq 'rift_native_buffer_compiler_host' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build librift_native_buffer_compiler_host for generic native-buffer compiler execution.' >&2
  exit 1
}
grep -Fq 'riftpp_editor_bridge' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libriftpp_editor_bridge for the permanent Rift++ editor JNI boundary.' >&2
  exit 1
}
for required_riftpp_mirror_contract in \
  'val verifyRiftppEditorPayload by tasks.registering' \
  '"src/main/java/com/riftpp/apphost/RiftppAppActivity.kt"' \
  '"src/main/cpp/editor/riftpp_editor_bridge.cpp"' \
  'dependsOn(verifyRiftppEditorPayload)'; do
  grep -Fq "$required_riftpp_mirror_contract" "$gradle_contract" || {
    echo "Builder Rift++ mirrored editor Gradle contract missing: $required_riftpp_mirror_contract" >&2
    exit 1
  }
done
if grep -Fq 'riftpp_dynamic_compiler_host' android/app/src/main/cpp/CMakeLists.txt; then
  echo 'Builder contract failed: Rift++-named native-buffer host resurfaced.' >&2
  exit 1
fi
for required_hot_command in \
  '"managed-status" -> managedStatus(' \
  '"managed-copy" -> managedCopy(' \
  '"compiler-status" -> compilerStatus(' \
  '"compiler-run" -> compilerRun(' \
  '"kotlin-compile" -> kotlinCompile('; do
  grep -Fq "$required_hot_command" "$riftbuild_source" || {
    echo "Builder contract is stale: RiftBuild hot-swap command missing: $required_hot_command" >&2
    exit 1
  }
done

# Long RiftShell/RiftBuild work must survive the MCP request window without reviving RiftCLI.
shell_executor_source="android/app/src/main/java/com/riftos/app/RiftShellExecutor.kt"
native_shell_source="android/app/src/main/java/com/riftos/app/RiftNativeShell.kt"
tool_host_source="android/app/src/main/java/com/riftos/app/RiftToolHost.kt"
managed_jvm_source="android/app/src/main/java/com/riftos/app/RiftManagedJvmToolService.kt"
for shell_job_source in "$shell_executor_source" "$native_shell_source" "$tool_host_source" "$managed_jvm_source"; do
  test -f "$shell_job_source" || {
    echo "Builder persistent RiftShell job contract is missing source: $shell_job_source" >&2
    exit 1
  }
done
for required_shell_executor_contract in \
  'fun submit(' \
  'fun jobStatus(' \
  'fun jobResult(' \
  'fun jobCancel(' \
  'fun jobList('; do
  grep -Fq "$required_shell_executor_contract" "$shell_executor_source" || {
    echo "Builder persistent RiftShell executor contract missing: $required_shell_executor_contract" >&2
    exit 1
  }
done
for required_native_shell_job_contract in \
  'SYNC_SHELL_TIMEOUT_MS = 10 * 60 * 1000L' \
  'MAX_SHELL_JOBS = 16' \
  'SHELL_JOB_RETENTION_MS = 10 * 60 * 1000L' \
  'MAX_SHELL_JOB_RETAINED_RESULT_BYTES = 2 * 1024 * 1024' \
  'rift.shell-job/1' \
  'rift.shell-jobs/1'; do
  grep -Fq "$required_native_shell_job_contract" "$native_shell_source" || {
    echo "Builder persistent RiftShell job contract missing: $required_native_shell_job_contract" >&2
    exit 1
  }
done
for required_shell_tool_contract in \
  'shouldSubmitShellJob(command)' \
  '"auto", "exec", "submit", "status", "result", "cancel", "list"' \
  '"kotlin-compile"'; do
  grep -Fq "$required_shell_tool_contract" "$tool_host_source" || {
    echo "Builder MCP RiftShell job routing contract missing: $required_shell_tool_contract" >&2
    exit 1
  }
done
for required_managed_jvm_contract in \
  'RUN_TIMEOUT_SECONDS = 10 * 60L' \
  'putString("status", "cancelled")' \
  'Process.killProcess(remotePid)'; do
  grep -Fq "$required_managed_jvm_contract" "$managed_jvm_source" || {
    echo "Builder managed JVM long-command contract missing: $required_managed_jvm_contract" >&2
    exit 1
  }
done
if grep -Fq 'SHELL_TIMEOUT_MS = 60_000L' "$native_shell_source" || grep -Fq 'RUN_TIMEOUT_SECONDS = 60L' "$managed_jvm_source"; then
  echo 'Builder contract failed: retired 60-second shell/compiler timeout resurfaced.' >&2
  exit 1
fi

for retired_riftpp_route in \
  'riftpp-compile-hot' \
  'prepare-riftpp-v0' \
  'prepare-riftpp-seed0-arm64' \
  'prepare-riftpp-app0' \
  'prepare-riftpp-editor'; do
  if grep -Fq "$retired_riftpp_route" "$riftbuild_source"; then
    echo "Builder contract is stale: retired Rift++ RiftBuild route resurfaced: $retired_riftpp_route" >&2
    exit 1
  fi
done
if grep -Fq 'riftpp-host' android/app/src/main/java/com/riftos/app/RiftNativeShell.kt; then
  echo 'Builder contract is stale: retired riftpp-host shell compiler surface resurfaced.' >&2
  exit 1
fi

: "${RIFT_SIGN_STORE:?Release signing identity required}"
: "${RIFT_SIGN_ALIAS:?Release key alias required}"
export RIFT_SIGN_STORE_PASS="${RIFT_SIGN_STORE_PASS:?Release store password required}"
export RIFT_SIGN_KEY_PASS="${RIFT_SIGN_KEY_PASS:?Release key password required}"

if ! timeout --signal=TERM --kill-after=30s "$SOURCE_CHECK_TIMEOUT" \
    npm run check >"$LOG_DIR/source-check.log" 2>&1; then
  echo "Source checks failed or exceeded $SOURCE_CHECK_TIMEOUT; APK build stopped." >&2
  exit 1
fi

if ! timeout --signal=TERM --kill-after=30s "$RIFTBUILD_TOOLCHAIN_TIMEOUT" \
    python3 "$SCRIPT_DIR/prepare-riftbuild-toolchain.py" "$SOURCE_DIR" \
    >"$LOG_DIR/riftbuild-toolchain.log" 2>&1; then
  echo "RiftBuild Android-host toolchain generation failed or exceeded $RIFTBUILD_TOOLCHAIN_TIMEOUT. Detailed log will be returned privately." >&2
  exit 1
fi
for generated_toolchain_file in \
  android/app/build/generated/riftosAssets/riftbuild/android-clang-v1.zip \
  android/app/build/generated/riftosJniLibs/arm64-v8a/libclang_exec.so \
  android/app/build/generated/riftosJniLibs/arm64-v8a/libld_lld_exec.so \
  android/app/build/generated/riftosJniLibs/arm64-v8a/libld_lld_shim.so \
  android/app/build/generated/riftosJniLibs/armeabi-v7a/libclang_exec.so \
  android/app/build/generated/riftosJniLibs/armeabi-v7a/libld_lld_exec.so \
  android/app/build/generated/riftosJniLibs/armeabi-v7a/libld_lld_shim.so; do
  test -s "$generated_toolchain_file" || {
    echo "RiftBuild generated toolchain payload missing or empty: $generated_toolchain_file" >&2
    exit 1
  }
done

# Native proof/compiler hosts must be rebuilt from the checked-out source. Keep
# the generated RiftBuild toolchain payload, but discard CMake/native packaging
# intermediates that can survive worker reuse across source revisions.
rm -rf \
  android/app/.cxx \
  android/.cxx \
  android/app/build/intermediates/cxx \
  android/app/build/intermediates/merged_native_libs \
  android/app/build/intermediates/stripped_native_libs

if ! timeout --signal=TERM --kill-after=30s "$GRADLE_VALIDATE_TIMEOUT" \
    gradle -p android --stacktrace \
      :app:verifyRiftOsAndroidSources \
      :app:verifyCodynexEditorPayload \
      :app:verifyRiftppEditorPayload \
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

