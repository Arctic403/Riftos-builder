#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = (ROOT / "scripts" / "riftos-build.sh").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts" / "verify-riftos-apk.sh").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "riftos-worker.yml").read_text(encoding="utf-8")
MANAGED_WORKFLOW = (ROOT / ".github" / "workflows" / "managed-compiler-worker.yml").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"{label}: stale {needle!r}")


for task in (
    ":app:verifyRiftOsAndroidSources",
    ":app:verifyCodynexEditorPayload",
    ":app:verifyRiftppEditorPayload",
    ":app:validateRiftBrowserWebViewOwnership",
):
    require(BUILD, task, "dedicated Gradle validation")

apphost_pattern = "com\\/riftpp\\/apphost"
require(BUILD, apphost_pattern, "builder Kotlin source derivation")
require(VERIFY, apphost_pattern, "APK Kotlin descriptor derivation")

for marker in (
    "SYNC_SHELL_TIMEOUT_MS = 10 * 60 * 1000L",
    "MAX_SHELL_JOBS = 16",
    "SHELL_JOB_RETENTION_MS = 10 * 60 * 1000L",
    "MAX_SHELL_JOB_RETAINED_RESULT_BYTES = 2 * 1024 * 1024",
    "RUN_TIMEOUT_SECONDS = 10 * 60L",
    '"auto", "exec", "submit", "status", "result", "cancel", "list"',
):
    require(BUILD, marker, "persistent RiftShell source preflight")

for retired in (
    "SHELL_TIMEOUT_MS = 60_000L",
    "RUN_TIMEOUT_SECONDS = 60L",
):
    require(BUILD, retired, "retired-timeout negative regression")

for marker in (
    "rift.shell-job/1",
    "rift.shell-jobs/1",
    "cancel_requested",
    "completed_after_cancel_request",
    "completed_result_too_large",
    "Managed JVM tool was cancelled",
):
    require(VERIFY, marker, "final APK persistent shell-job proof")

for entry in (
    'lib/arm64-v8a/libriftpp_editor_bridge.so',
    'lib/armeabi-v7a/libriftpp_editor_bridge.so',
):
    require(VERIFY, entry, "Rift++ editor JNI bridge APK proof")

for marker in (
    "riftpp_editor_bridge",
    '"src/main/java/com/riftpp/apphost/RiftppAppActivity.kt"',
    '"src/main/cpp/editor/riftpp_editor_bridge.cpp"',
    "dependsOn(verifyRiftppEditorPayload)",
):
    require(BUILD, marker, "Rift++ mirrored editor preflight")

# Regression guard for the removed embedded RiftBuild variable that caused
# Build 37721469811 to fail under bash -u before source/Gradle validation.
forbid(BUILD, '"$riftbuild_source"', "retired embedded RiftBuild source variable")
require(BUILD, "retired Kotlin compiler job routing resurfaced", "ToolHost legacy Kotlin job-route retirement")
require(BUILD, 'riftbuild_platform_source="android/app/src/main/java/com/riftos/app/RiftBuildPlatformTools.kt"', "canonical platform owner")
for current_command in (
    '"compiler-status" -> buildLocal.compilerStatus(',
    '"compiler-run" -> buildLocal.compilerRun(',
    '"jvm-status" -> buildLocal.jvmToolchainStatus()',
    '"jvm-dex" -> buildLocal.dexJvmClasses(',
):
    require(BUILD, current_command, "generic compiler and DEX source contract")
for retired_command in (
    """'"managed-status" -> managedStatus('""",
    """'"managed-copy" -> managedCopy('""",
    """'"kotlin-compile" -> kotlinCompile('""",
):
    forbid(BUILD, retired_command, "retired embedded compiler command contract")

for marker in (
    '"pack-rapp" -> packRapp(',
    '"install-rapp" -> installRapp(',
    '"launch-rapp" -> launchRapp(',
    '"rapp-list" -> JSONObject()',
    '"src/main/java/com/riftos/app/RiftAppAbi.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppAdapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppWs15Adapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppGenericAdapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappJsonAdapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappQuickJsExecutor.kt"',
    '"src/main/java/com/riftos/app/RiftRappCapabilityBroker.kt"',
    '"src/main/java/com/riftos/app/RiftRappAbsoluteView.kt"',
    '"src/main/java/com/riftos/app/RiftRappHost.kt"',
    '"src/main/java/com/riftos/app/RiftRappManager.kt"',
    "rappHost.onResume()",
    "rappHost.onPause()",
    'const val SCHEMA = "riftos-app-abi/1"',
    'const val HOST_EFFECT_RESULT = 13',
    '"riftpp-rpa2-v1"',
    '"riftpp-rws2-rui3-v1"',
    '"riftpp-generic-v1"',
    '"json-generic-v1"',
    '"json-frame-v1"',
    'object RiftAppExecutionKind',
    '"native-buffer-v1"',
    '"quickjs-v1"',
    'class RiftRappQuickJsExecutor',
    'RiftAppExecutionKind.QUICKJS',
    "private const val RPE4_MAGIC",
    "private const val RWS4_MAGIC",
    "decodeOutput(",
    "pendingEvents",
    "resolveHostEffect(",
    "manager.persistState(",
    'private const val STATE_ENTRY = "state.bin"',
    "val effectiveProgram =",
    "fun persistState(",
    "RAPP persisted state is out of bounds",
    "RAPP persisted state escaped program root",
    "state.copyOf()",
    "writeAtomic(",
    "private fun createInput(",
    "private fun createAction(",
    "addTextChangedListener(",
    "override fun dispatchKeyEvent(",
    "override fun onSizeChanged(",
    "readPermissions(",
    "RiftAppAdapters.find(",
    "class RiftRappCapabilityBroker",
    "setting:permissions:",
    'const val SIGNING_IDENTITY = "signing.identity"',
    'Capability.SIGNING_IDENTITY',
    '"readBytes"',
    '"writeBytes"',
    '"stat"',
    '"mkdir"',
    '"move"',
    "riftos-fs-bytes-read/1",
    "riftos-fs-bytes-write/1",
    "MAX_BINARY_CHUNK_BYTES",
    "MAX_BINARY_FILE_BYTES",
    '"signSha256RsaPkcs1"',
    '"verifySha256RsaPkcs1"',
    "certificateDerBase64",
    "publicKeyDerBase64",
    "riftos-signing-verify/1",
    "riftos-signing-identity/1",
    "riftbuild-apk-v2-rsa-v1",
    "SHA256withRSA",
    "Capability.BUILD_LOCAL",
    '"toolchainStatus"',
    '"compilerRun"',
    '"jvmDex"',
    "BUILD_OPERATION_TIMEOUT_MS",
    "MAX_EFFECT_DEPTH = 1024",
    "private val rappManager by lazy",
    "RiftNativeBufferCompilerService.compile",
    "RiftBoundedAsync.submit",
    "RAPP host must not execute native payloads directly in the RiftOS desktop process",
):
    require(BUILD, marker, "RiftOS generic RAPP builder contract")

for marker in (
    "pack-rapp",
    "install-rapp",
    "launch-rapp",
    "rapp-list",
    "riftos.rapp-project/1",
    "riftos.rapp/1",
    "riftos-app-abi/1",
    "riftpp-rpa2-v1",
    "riftpp-rws2-rui3-v1",
    "riftpp-generic-v1",
    "Generic Rift++ response magic is invalid",
    "RAPP pending event queue exceeded bound",
    "RAPP host effect chain exceeded bound",
    "state.bin",
    "RAPP persisted state is out of bounds",
    "RAPP persisted state escaped program root",
    "Installed RAPP state is not a file",
    "setting:permissions:",
    "fs.read",
    "fs.write",
    "readBytes",
    "writeBytes",
    "riftos-fs-bytes-read/1",
    "riftos-fs-bytes-write/1",
    "signing.identity",
    "signSha256RsaPkcs1",
    "riftos-signing-identity/1",
    "riftbuild-apk-v2-rsa-v1",
    "SHA256withRSA",
    "clipboard.read",
    "clipboard.write",
    "window.title",
):
    require(VERIFY, marker, "final APK generic RAPP proof")

for marker in (
    "scripts/test-riftpp-shell.mjs",
    "headlessJs.executeRiftpp(args, cwd)",
    "riftpp-shell-self-test/3",
    "canonicalUtf8Bytes",
    "run-stateful",
    "exec-stateful",
    "run-software",
    "exec-software",
    "text-model-benchmark",
    "semantic-compat",
    "HEADLESS QUICKJS",
):
    require(BUILD, marker, "Rift++ headless source contract")

for marker in (
    "riftpp-shell-self-test/3",
    "riftpp-text-model-benchmark-v2",
    "riftpp-semantic-compat-device-suite/1",
    "headless-quickjs",
    "run-stateful",
    "exec-stateful",
    "run-software",
    "exec-software",
    "state.load",
    "state.save",
    "state.remove",
    "software.caseId",
    "software.source",
    "text-model-benchmark",
    "semantic-compat",
    "Only SHA-256 is available",
    "out[i] = raw[i] & 255;",
    "Array.from(view, value => value & 255)",
):
    require(VERIFY, marker, "final APK Rift++ headless proof")



for stale in (
    "one-time Rift++ legacy-editor native bootstrap",
    "future Rift++ native-editor",
    "Rift++ legacy-editor native bootstrap",
):
    forbid(BUILD, stale, "builder shell architecture")
    forbid(README, stale, "builder documentation architecture")

require(WORKFLOW, "python3 worker/scripts/test-builder-contracts.py", "workflow builder self-test")
require(WORKFLOW, "worker/scripts/test-builder-contracts.py", "workflow Python syntax validation")
require(README, "persistent RiftShell jobs", "builder documentation shell-job contract")
require(README, "single permanent Rift++ editor", "builder documentation editor contract")
require(BUILD, '<package android:name="com.riftpp.editor" />', "external Rift++ editor Binder visibility preflight")
require(README, "external editor Binder bridge", "builder documentation Binder visibility contract")
require(README, "not used as generic RiftBuild install/launch authority", "builder documentation generic installer separation")
require(README, "RiftLocalBuildCapability", "builder documentation build.local owner")
require(README, "RiftJvmDexService", "builder documentation JVM DEX owner")
require(README, "RiftBuildPlatformTools", "builder documentation platform tool owner")
require(README, "RiftApkV2Verifier", "builder documentation verifier-only owner")
require(README, "RiftRappCapabilityBroker", "builder documentation capability broker")
require(README, "state.bin", "builder documentation durable RAPP state")
require(README, "riftpp-generic-v1", "builder documentation forward RAPP adapter")
require(README, "compatibility lanes", "builder documentation compatibility adapters")
require(README, "headless QuickJS", "builder documentation retained headless runtime")
require(README, "test-riftpp-shell.mjs", "builder documentation headless Rift++ source gate")
require(BUILD, "retired riftpp-host shell compiler surface resurfaced", "builder retired Rift++ compiler-host guard")
require(README, "RiftOS APK worker does not use `actions/upload-artifact`", "builder documentation APK artifact policy")
require(README, "managed compiler worker intentionally uses `actions/upload-artifact@v4`", "builder documentation compiler artifact policy")
require(MANAGED_WORKFLOW, "actions/upload-artifact@v4", "managed compiler artifact return lane")

# DEX smoke requirements must never also be forbidden as substrings: the surviving
# generic riftbuild-kotlin-toolchain-status/2 schema contains "toolchain-status".
# Assert semantic markers remain while guarding the exact retired shell route in source.
require(VERIFY, "'riftbuild-kotlin-toolchain-status/2'", "active generic JVM status marker")
require(VERIFY, "'riftbuild-native-toolchain-status-v1'", "unique retired native toolchain schema guard")
require(BUILD, '"toolchain-status"[[:space:]]*->', "exact retired shell toolchain-status route guard")
dex_required, dex_forbidden = [], []
for marker_block, operation in re.findall(
    r'for (?:retired_marker|marker) in \\\n(.*?); do\s*\n\s*(require_dex_string|forbid_dex_string)',
    VERIFY,
    re.S,
):
    markers = re.findall(r"'([^']+)'", marker_block)
    if operation == "require_dex_string":
        dex_required.extend(markers)
    else:
        dex_forbidden.extend(markers)
if not dex_required or not dex_forbidden:
    raise AssertionError("Builder DEX marker lists are missing")
for forbidden_marker in dex_forbidden:
    for required_marker in dex_required:
        if forbidden_marker in required_marker:
            raise AssertionError(
                "APK DEX smoke marker contradiction: forbidden "
                + repr(forbidden_marker) + " is inside required " + repr(required_marker)
            )

# C0.1 APK gate: removed editor client schema is forbidden, while the
# still-shipping mirrored editor service protocols remain positively verified.
require(VERIFY, "for bridge_marker in ", "Codynex service marker loop")
client_marker_block = VERIFY.split("for bridge_marker in ", 1)[1].split("; do", 1)[0]
for marker in ("codynex-editor-folder-push/1", "codynex-editor-folder-pull/1"):
    if marker in client_marker_block:
        raise AssertionError("Retired editor client marker must not be required in APK: " + marker)
    require(VERIFY, "'" + marker + "'", "retired editor client negative DEX marker")
require(VERIFY, "for retired_editor_client_marker in", "signed DEX editor-client absence gate")
require(VERIFY, 'forbid_dex_string "$retired_editor_client_marker"', "signed DEX editor-client absence call")
require(VERIFY, "'codynex-editor-bridge-compile/1'", "still-present editor service proof")

# C0.1 correction: source graph requires deleting unused editor Binder clients.
# Restore neither the files nor Gradle declarations to bypass reachability.
for marker in (
    "project editor bridge client resurfaced",
    "project editor bridge client remains in Gradle",
    "RiftCodynexEditorBridgeClient.kt",
    "RiftppEditorBridgeClient.kt",
):
    require(BUILD, marker, "retired editor client absence regression")

# C0.1: editor workflows are external software, not RiftShell built-ins.
# Their independently compiled bridge services remain required only until the
# later mirrored-editor APK-payload removal gate.
for marker in (
    "executeCodynexEditorCommand",
    "executeRiftppEditorCommand",
    "Rift++ editor-specific native shell command resurfaced",
    "Codynex editor-specific native shell command resurfaced",
):
    require(BUILD, marker, "external editor shell ownership guard")
for marker in (
    "'usage: riftpp-editor'",
    "'usage: codynex-editor'",
    "forbid_dex_string \"$retired_editor_shell\"",
    "'riftpp-editor-native-compile/1'",
    "'codynex-editor-bridge-compile/1'",
):
    require(VERIFY, marker, "editor shell exclusion and independent service proof")

print("ok - RiftOS builder contracts are internally consistent")
