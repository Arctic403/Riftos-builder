#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:?usage: riftos-build.sh <source-dir>}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
LOG_DIR="${RUNNER_TEMP:?}/riftos-private-logs"
OUT_DIR="${RUNNER_TEMP:?}/riftos-output"
mkdir -p "$LOG_DIR" "$OUT_DIR"

for required_command in timeout node npm gradle git grep sed sha256sum; do
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
GRADLE_VALIDATE_TIMEOUT="${GRADLE_VALIDATE_TIMEOUT:-6m}"
GRADLE_BUILD_TIMEOUT="${GRADLE_BUILD_TIMEOUT:-20m}"
APK_VERIFY_TIMEOUT="${APK_VERIFY_TIMEOUT:-3m}"

# Fail before the expensive Android build if the builder-side smoke gate itself is malformed.
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

# Builder-owned syntax preflight for the source-gate entrypoints. This runs before the
# source-owned validator so a malformed validator cannot hide its own parse failure.
for source_gate_script in   scripts/validate-rift-wiring.mjs   scripts/validate-rift-transport.mjs   scripts/validate-rift-docs.mjs   scripts/test-rift-cli-push-channel.mjs   scripts/test-rift-cli-batch-v2.mjs   scripts/test-rift-local-agent-batch.mjs   scripts/test-rift-mcp-operation-journal.mjs   scripts/test-rift-debug-hub.mjs   scripts/test-riftbuild-native.mjs   scripts/test-riftllm-bridge.mjs   scripts/test-semnexis-bootstrap.mjs   scripts/test-semnexis-arm32-exec.mjs   scripts/test-semnexis-shell.mjs; do
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
# source tests/Gradle: every mandatory Kotlin filename must declare a matching top-level
# class/object/interface because verify-riftos-apk.sh derives that DEX descriptor from the file name.
root_gradle_contract="android/build.gradle.kts"
gradle_contract="android/app/build.gradle.kts"
grep -Fq 'org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.10' "$root_gradle_contract" || {
  echo 'Builder contract is stale: RiftOS root Gradle must pin Kotlin Gradle plugin 2.4.10 for QuickJS 1.0.14 metadata compatibility.' >&2
  exit 1
}
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
  'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0'; do
  grep -Fq "$required_gradle_contract" "$gradle_contract" || {
    echo "Builder contract is stale: expected Gradle contract missing: $required_gradle_contract" >&2
    exit 1
  }
done
mapfile -t required_native_sources < <(
  sed -nE 's/.*"(src\/main\/java\/com\/riftos\/app\/[A-Za-z0-9_]+\.kt)".*/\1/p' "$gradle_contract"
)
test "${#required_native_sources[@]}" -gt 0 || { echo 'Builder contract preflight found no mandatory Kotlin sources.' >&2; exit 1; }
for source_rel in "${required_native_sources[@]}"; do
  source="android/app/$source_rel"
  test -f "$source" || { echo "Builder contract preflight missing mandatory Kotlin source: $source_rel" >&2; exit 1; }
  class_name="${source_rel##*/}"
  class_name="${class_name%.kt}"
  if ! grep -Eq "^[[:space:]]*((public|private|internal|protected)[[:space:]]+)?((data|sealed|enum|annotation|value)[[:space:]]+)?(class|object|interface)[[:space:]]+${class_name}([[:space:]<(::{]|$)" "$source"; then
    echo "Builder DEX verifier assumption is stale: $source_rel does not declare top-level $class_name." >&2
    exit 1
  fi
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

# Codynex C0 editor/provider contract. This surface spans RiftOS plus mirrored editor payload,
# so validate it explicitly before source tests or Gradle rather than waiting for Kotlin/AAPT.
manifest_contract="android/app/src/main/AndroidManifest.xml"
provider_source="android/app/src/main/java/com/riftos/app/CodynexCompilerProvider.kt"
editor_activity="android/app/src/main/java/com/codynex/editorapp/MainActivity.kt"
editor_toolchain="android/app/src/main/java/com/codynex/editorapp/Source0SelfHostToolchainPort.kt"
editor_bootstrap="android/app/src/main/java/com/codynex/editorapp/BootstrapArtifacts.kt"
editor_vm_bridge_kt="android/app/src/main/java/com/codynex/editorapp/Vm1Bridge.kt"
editor_vm_bridge_cpp="android/app/src/main/cpp/editor/editor_vm_bridge.cpp"
riftbuild_source="android/app/src/main/java/com/riftos/app/RiftBuildLocalExecutor.kt"

for editor_contract_file in \
  "$manifest_contract" \
  "$provider_source" \
  "$editor_activity" \
  "$editor_toolchain" \
  "$editor_bootstrap" \
  "$editor_vm_bridge_kt" \
  "$editor_vm_bridge_cpp" \
  "$riftbuild_source"; do
  test -f "$editor_contract_file" || {
    echo "Builder Codynex C0 editor contract is missing: $editor_contract_file" >&2
    exit 1
  }
done

grep -Fq '"src/main/java/com/riftos/app/CodynexCompilerProvider.kt"' "$gradle_contract" || {
  echo 'Builder contract is stale: CodynexCompilerProvider.kt is not mandatory in verifyRiftOsAndroidSources.' >&2
  exit 1
}
node -e '
  const fs = require("fs");
  const xml = fs.readFileSync("android/app/src/main/AndroidManifest.xml", "utf8");
  const provider = xml.match(/<provider\b[^>]*android:name="\.CodynexCompilerProvider"[^>]*\/>/s)?.[0] || "";
  for (const required of [
    "android:name=\".CodynexCompilerProvider\"",
    "android:authorities=\"com.riftos.app.codynexcompiler\"",
    "android:exported=\"true\"",
    "android:grantUriPermissions=\"false\"",
  ]) {
    if (!provider.includes(required)) {
      console.error("Builder Codynex provider manifest element missing: " + required);
      process.exit(1);
    }
  }
'

for required_provider_contract in \
  'class CodynexCompilerProvider' \
  'METHOD_COMPILE = "compile-c0"' \
  'EDITOR_PACKAGE = "com.codynex.editor"' \
  'EDITOR_CERT_SHA256 =' \
  '9874e844c24fe92c65908ce9b3cfb192f87774984a9e4fc600d883badcbe19b5' \
  'COMPILER_VERSION =' \
  'codynex-c0-ref/0.11.0' \
  'MAX_SOURCE_BYTES = 256 * 1024' \
  'MAX_VM1_BYTES = 64 * 1024' \
  'runtime.executeQuickJs' \
  '/workspace/Codynex/external/language/l0/compiler/c0_reference.js'; do
  grep -Fq "$required_provider_contract" "$provider_source" || {
    echo "Builder Codynex provider source contract missing: $required_provider_contract" >&2
    exit 1
  }
done

for required_editor_contract in \
  'File(workspaceRoot, "main.cx")' \
  'C0 0.11.0 via' \
  'RiftOS QuickJS -> VM1'; do
  grep -Fq "$required_editor_contract" "$editor_activity" || {
    echo "Builder Codynex editor activity contract missing: $required_editor_contract" >&2
    exit 1
  }
done

for required_editor_toolchain in \
  'com.riftos.app.codynexcompiler' \
  'COMPILE_METHOD = "compile-c0"' \
  'contentResolver.call' \
  'Vm1Bridge.run' \
  'MAX_SOURCE_BYTES = 256 * 1024' \
  'MAX_CANDIDATE_BYTES = 64 * 1024'; do
  grep -Fq "$required_editor_toolchain" "$editor_toolchain" || {
    echo "Builder Codynex editor toolchain contract missing: $required_editor_toolchain" >&2
    exit 1
  }
done

for required_editor_packer_contract in \
  '"prepare-codynex-editor" -> prepareCodynexEditor(' \
  'EDITOR_HOST_APK_ENTRY = "lib/armeabi-v7a/libcodynex_editor_vm.so"' \
  'buildEditorManifestStartElement("queries", emptyList())' \
  'editorManifestStringAttr("name", "com.riftos.app")'; do
  grep -Fq "$required_editor_packer_contract" "$riftbuild_source" || {
    echo "Builder Codynex editor packer contract missing: $required_editor_packer_contract" >&2
    exit 1
  }
done

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
  android/app/src/main/cpp/mc0/codynex_mc0_host.cpp \
  android/app/src/main/cpp/mc1/codynex_mc1a_host.cpp \
  android/app/src/main/cpp/mc1/codynex_mc1b_host.cpp \
  android/app/src/main/cpp/riftpp/riftpp_app0_host.cpp \
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
grep -Fq 'codynex_mc0_host' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libcodynex_mc0_host for RiftBuild MC0 proof packaging.' >&2
  exit 1
}
grep -Fq 'codynex_mc1a_host' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libcodynex_mc1a_host for RiftBuild MC1-A proof packaging.' >&2
  exit 1
}
grep -Fq 'codynex_mc1b_host' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libcodynex_mc1b_host for RiftBuild MC1-B proof packaging.' >&2
  exit 1
}
grep -Fq 'codynex_editor_vm' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libcodynex_editor_vm for Codynex editor Preview packaging.' >&2
  exit 1
}
grep -Fq 'riftpp_app0_host' android/app/src/main/cpp/CMakeLists.txt || {
  echo 'Builder contract is stale: CMake must build libriftpp_app0_host for generated-runtime App0 packaging.' >&2
  exit 1
}
grep -Fq '"prepare-riftpp-app0" -> prepareRiftppApp0(' "$riftbuild_source" || {
  echo 'Builder contract is stale: RiftBuild must expose the bounded Rift++ App0 preparation lane.' >&2
  exit 1
}

: "${RIFT_SIGN_STORE:?Release signing identity required}"
: "${RIFT_SIGN_ALIAS:?Release key alias required}"
export RIFT_SIGN_STORE_PASS="${RIFT_SIGN_STORE_PASS:?Release store password required}"
export RIFT_SIGN_KEY_PASS="${RIFT_SIGN_KEY_PASS:?Release key password required}"

if ! timeout --signal=TERM --kill-after=30s "$SOURCE_CHECK_TIMEOUT" \
    npm run check >"$LOG_DIR/source-check.log" 2>&1; then
  echo "Source checks failed or exceeded $SOURCE_CHECK_TIMEOUT; APK build stopped." >&2
  exit 1
fi

if ! timeout --signal=TERM --kill-after=30s "$GRADLE_VALIDATE_TIMEOUT" \
    gradle -p android --stacktrace \
      :app:verifyRiftOsAndroidSources \
      :app:validateRiftBrowserWebViewOwnership \
      --no-daemon >"$LOG_DIR/gradle-validation.log" 2>&1; then
  echo "RiftOS Gradle validation failed or exceeded $GRADLE_VALIDATE_TIMEOUT before compilation. Detailed log will be returned privately." >&2
  exit 1
fi

if ! timeout --signal=TERM --kill-after=30s "$GRADLE_BUILD_TIMEOUT" \
    gradle -p android --stacktrace --build-cache :app:assembleRelease --no-daemon \
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
