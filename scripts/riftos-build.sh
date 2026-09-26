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


# N1.8.4 machine phase authority is source, not documentation. Guard its basic transport
# contract independently before source-owned tests execute; the source regression owns the
# deeper lifecycle/source/run semantics.
PHASE_AUTHORITY_FILE="observer/phase-authority.json"
[ -f "$PHASE_AUTHORITY_FILE" ] || {
  echo "RiftOS N1.8.4 phase authority missing: $PHASE_AUTHORITY_FILE" >&2
  exit 1
}
node -e '
  const fs = require("node:fs");
  const p = process.argv[1];
  const stat = fs.statSync(p);
  if (stat.size > 64 * 1024) {
    console.error("RiftOS N1.8.4 phase authority exceeds 64 KiB");
    process.exit(1);
  }
  let value;
  try {
    value = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (error) {
    console.error("RiftOS N1.8.4 phase authority is not valid JSON: " + error.message);
    process.exit(1);
  }
  if (value?.schema !== "rift-observer-phase-authority-v1") {
    console.error("RiftOS N1.8.4 phase authority schema mismatch");
    process.exit(1);
  }
' "$PHASE_AUTHORITY_FILE"

# N2.0 machine contract/phase authority are source, not documentation. Guard the
# lifecycle, runtime-inactive boundary and frozen component identities independently.
N2_CONTRACT_FILE="riftmemory/n2-contract-v1.json"
N2_PHASE_AUTHORITY_FILE="riftmemory/n2-phase-authority.json"
for required_n2_file in "$N2_CONTRACT_FILE" "$N2_PHASE_AUTHORITY_FILE"; do
  [ -f "$required_n2_file" ] || {
    echo "RiftOS N2.0 machine authority missing: $required_n2_file" >&2
    exit 1
  }
  [ "$(wc -c < "$required_n2_file")" -le 65536 ] || {
    echo "RiftOS N2.0 machine authority exceeds 64 KiB: $required_n2_file" >&2
    exit 1
  }
done
node -e '
  const fs = require("node:fs");
  const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const phase = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  const benchmarkRule = "NO_PERFORMANCE_OR_COMPARATIVE_BENCHMARKS_UNTIL_FULL_RIFTCLI_COMPLETE_AND_LIVE";
  if (contract?.schema !== "rift-memory-n2-contract-v1" ||
      contract?.phase !== "N2.0" ||
      contract?.status !== "source-implemented" ||
      contract?.promotion !== "pending-builder-install-proof" ||
      contract?.runtimeActivation !== false ||
      contract?.globalBenchmarkRule !== benchmarkRule) {
    console.error("RiftOS N2.0 machine contract lifecycle mismatch");
    process.exit(1);
  }
  if (contract?.terminologySha256 !== "bf18c5f2db272c5a66723879ab021a3ffc42483c4cd4fc6597d10bd96fc949d8" ||
      contract?.memoryStoreSha256 !== "68c46266e926e546e95543eb7a2092576c91499f810bcc5d483671d706823d16" ||
      contract?.correctnessCorpusSha256 !== "4ec6cd3e133de7c9a4f5f4d91c48b0873df02fb79a7b19727c96256b6e4687c4" ||
      contract?.correctnessThresholdsSha256 !== "a6307031907834e0bb4060d24209a98706df4d0bfe39a7936cc5750fb06f6801" ||
      contract?.contractPayloadSha256 !== "bf70f093f303f745b2e861431f2890be87367160c7cfbbd1c1a22004c49b4bb2") {
    console.error("RiftOS N2.0 frozen hash mismatch");
    process.exit(1);
  }
  const expectedMacroPhases = [
    ["N2.1", "N2.2"],
    ["N2.3", "N2.4"],
    ["N2.5", "N2.6"],
    ["N2.7", "N2.8"],
    ["N2.9"],
    ["N2.10", "N2.11"],
  ];
  if (phase?.schema !== "rift-memory-n2-phase-authority-v1" ||
      phase?.programStatus !== "N2.0-N2.12 PROMOTED / N2-M1 + N2-M2 + N2-M3 + N2-M4 + N2-M5 + N2-M6 PROMOTED; N2 COMPLETE" ||
      phase?.runtimeStatus !== "N2 CANONICAL MEMORY RUNTIME INACTIVE; N2-M1 + N2-M2 + N2-M3 + N2-M4 + N2-M5 + N2-M6 PROMOTED DIAGNOSTICS; N2.12 FINAL CORRECTNESS GATE PROMOTED" ||
      phase?.n18Prerequisite !== "SATISFIED" ||
      phase?.benchmarkRule !== benchmarkRule ||
      phase?.contractLifecycleSemantics !== "immutable-N2.0-freeze-snapshot; current lifecycle is authoritative only in this phase-authority file" ||
      phase?.phases?.length !== 13 ||
      phase?.phases?.[0]?.status !== "promoted" ||
      phase?.phases?.[0]?.promotedSourceSha !== "f6bf12b9fb452cc128e9290fd73599297ba134f2" ||
      String(phase?.phases?.[0]?.builderRunNumber) !== "341" ||
      phase?.phases?.slice(1, 3).some(row => row.status !== "promoted" || row.promotedSourceSha !== "694c1e31a6c3f4bd4317edd121208be894be2586" || String(row.builderRunNumber) !== "346") ||
      phase?.phases?.slice(3, 5).some(row => row.status !== "promoted" || row.promotedSourceSha !== "18f1156075e08cb94573a9392031ac64552313f2" || String(row.builderRunNumber) !== "350") ||
      phase?.phases?.slice(5, 7).some(row => row.status !== "promoted" || row.promotedSourceSha !== "62382a94f50dd6052e1754c1496da2a0f794c0af" || String(row.builderRunNumber) !== "355") ||
      phase?.phases?.slice(7, 9).some(row => row.status !== "promoted" || row.promotedSourceSha !== "d39960832a701311461058670b5b93597ae612c9" || String(row.builderRunNumber) !== "368") ||
      phase?.phases?.[9]?.status !== "promoted" ||
      phase?.phases?.[9]?.promotedSourceSha !== "d650e57dff09a878f02edfef7e175ed02d42f750" ||
      String(phase?.phases?.[9]?.builderRunNumber) !== "370" ||
      phase?.phases?.slice(10, 12).some(row => row.status !== "promoted" || row.promotedSourceSha !== "921d32ff295921be8783ca4ce8395ba5ee029553" || String(row.builderRunNumber) !== "376") ||
      phase?.phases?.[12]?.status !== "promoted" ||
      phase?.phases?.[12]?.promotedSourceSha !== "9e75b0f76fd61ba80ca4c241a41532253bdb4c47" ||
      String(phase?.phases?.[12]?.builderRunNumber) !== "378" ||
      phase?.macroImplementationPlan?.[0]?.status !== "promoted" ||
      phase?.macroImplementationPlan?.[1]?.status !== "promoted" ||
      phase?.macroImplementationPlan?.[2]?.status !== "promoted" ||
      phase?.macroImplementationPlan?.[3]?.status !== "promoted" ||
      phase?.macroImplementationPlan?.[4]?.status !== "promoted" ||
      phase?.macroImplementationPlan?.[5]?.status !== "promoted" ||
      JSON.stringify(phase?.macroImplementationPlan?.map(row => row.phases)) !== JSON.stringify(expectedMacroPhases) ||
      !String(phase?.macroPlanRule || "").includes("execution groupings only") ||
      !String(phase?.macroPlanRule || "").includes("N2.12 remains a separate final correctness/adversarial promotion gate")) {
    console.error("RiftOS N2 phase authority lifecycle/macro-plan mismatch");
    process.exit(1);
  }
' "$N2_CONTRACT_FILE" "$N2_PHASE_AUTHORITY_FILE"

# Builder-owned syntax preflight for the source-gate entrypoints. This runs before the
# source-owned validator so a malformed validator cannot hide its own parse failure.
for source_gate_script in   scripts/validate-rift-wiring.mjs   scripts/validate-rift-transport.mjs   scripts/validate-rift-docs.mjs   scripts/test-rift-workspace-records.mjs   scripts/test-rift-patch-sessions.mjs   scripts/test-rift-cli-n3-contract-v1.mjs   scripts/test-rift-cli-authority-convergence.mjs   scripts/test-rift-mcp-cancellation.mjs   scripts/test-rift-shell-git.mjs   scripts/test-rift-cli-push-channel.mjs   scripts/test-rift-cli-batch-v2.mjs   scripts/test-rift-debug-hub.mjs   scripts/test-rift-integrity-v1.mjs   scripts/test-rift-propagation-v1.mjs   scripts/test-rift-cross-boundary-contracts-v1.mjs   scripts/test-rift-documentation-claims-v1.mjs   scripts/test-rift-proof-obligations-v1.mjs   scripts/test-rift-observer-adversarial-v1.mjs   scripts/test-rift-semantic-impact-v1.mjs   scripts/test-rift-memory-n2-contract-v1.mjs   scripts/test-rift-memory-n2-m1-v1.mjs   scripts/test-rift-memory-n2-m2-v1.mjs   scripts/test-rift-memory-n2-m3-v1.mjs   scripts/test-rift-memory-n2-m4-v1.mjs   scripts/test-rift-memory-n2-m5-v1.mjs   scripts/test-rift-memory-n2-m6-v1.mjs   scripts/test-rift-memory-n2-final-v1.mjs   scripts/test-riftllm-training-v2.mjs; do
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
    "node scripts/test-rift-workspace-records.mjs",
    "node scripts/test-rift-patch-sessions.mjs",
    "node scripts/test-rift-cli-n3-contract-v1.mjs",
    "node scripts/test-rift-cli-authority-convergence.mjs",
    "node scripts/test-rift-mcp-cancellation.mjs",
    "node scripts/test-rift-shell-git.mjs",
    "node scripts/test-rift-cli-push-channel.mjs",
    "node scripts/test-rift-cli-batch-v2.mjs",
    "node scripts/test-rift-debug-hub.mjs",
    "node scripts/test-rift-integrity-v1.mjs",
    "node scripts/test-rift-propagation-v1.mjs",
    "node scripts/test-rift-cross-boundary-contracts-v1.mjs",
    "node scripts/test-rift-documentation-claims-v1.mjs",
    "node scripts/test-rift-proof-obligations-v1.mjs",
    "node scripts/test-rift-observer-adversarial-v1.mjs",
    "node scripts/test-rift-semantic-impact-v1.mjs",
    "node scripts/test-rift-memory-n2-contract-v1.mjs",
    "node scripts/test-rift-memory-n2-m1-v1.mjs",
    "node scripts/test-rift-memory-n2-m2-v1.mjs",
    "node scripts/test-rift-memory-n2-m3-v1.mjs",
    "node scripts/test-rift-memory-n2-m4-v1.mjs",
    "node scripts/test-rift-memory-n2-m5-v1.mjs",
    "node scripts/test-rift-memory-n2-m6-v1.mjs",
    "node scripts/test-rift-memory-n2-final-v1.mjs",
    "node scripts/test-riftllm-training-v2.mjs",
  ]) {
    if (!transport.includes(required)) {
      console.error("Builder contract is stale: check:transport missing " + required);
      process.exit(1);
    }
  }
'

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
grep -Fq '"src/main/java/com/riftos/app/RiftMutationFence.kt"' "$gradle_contract" || {
  echo 'Builder contract is stale: RiftOS Gradle must include RiftMutationFence.kt in the mandatory native source snapshot.' >&2
  exit 1
}
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

# Required native subsystems must remain real C++ builds, not Kotlin-only placeholders.
for native_source in \
  android/app/src/main/cpp/CMakeLists.txt \
  android/app/src/main/cpp/riftcli/rift_cli_core.cpp \
  android/app/src/main/cpp/riftcli/rift_cli_core.h \
  android/app/src/main/cpp/riftcli/rift_cli_jni.cpp \
  android/app/src/main/cpp/mc0/codynex_mc0_host.cpp \
  android/app/src/main/cpp/mc1/codynex_mc1a_host.cpp \
  android/app/src/main/cpp/mc1/codynex_mc1b_host.cpp \
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
