#!/usr/bin/env python3
from pathlib import Path

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

for marker in (
    '"pack-rapp" -> packRapp(',
    '"install-rapp" -> installRapp(',
    '"launch-rapp" -> launchRapp(',
    '"rapp-list" -> JSONObject()',
    '"src/main/java/com/riftos/app/RiftAppAbi.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppAdapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppWs15Adapter.kt"',
    '"src/main/java/com/riftos/app/RiftRappRiftppGenericAdapter.kt"',
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
require(README, "persistent", "builder documentation shell-job contract")
require(README, "single permanent Rift++ editor", "builder documentation editor contract")
require(BUILD, '<package android:name="com.riftpp.editor" />', "external Rift++ editor Binder visibility preflight")
require(README, "external editor Binder bridge", "builder documentation Binder visibility contract")
require(README, "not used as generic RiftBuild install/launch authority", "builder documentation generic installer separation")
require(README, "riftpp-generic-v1", "builder documentation forward RAPP adapter")
require(README, "RPE4", "builder documentation generic RAPP event envelope")
require(README, "RWS4", "builder documentation generic RAPP response envelope")
require(README, "state.bin", "builder documentation durable RAPP state")
require(README, "effective program/state", "builder documentation RAPP state reload")
require(README, "RiftRappCapabilityBroker", "builder documentation capability broker")
require(README, "compatibility lanes", "builder documentation compatibility adapters")
require(README, "test-riftpp-shell.mjs", "builder documentation headless Rift++ source gate")
require(README, "run-stateful", "builder documentation stateful Rift++ shell")
require(README, "run-software", "builder documentation software-test Rift++ shell")
require(README, "canonical UTF-8", "builder documentation Rift++ text boundary")
require(README, "headless QuickJS", "builder documentation headless runtime")
require(README, "compatibility/reference `riftpp` shell boundary", "builder documentation retained Rift++ shell status")
require(README, "Historical Rift++ Android-native R3–R8 `riftpp-host` proof lanes remain evidence", "builder documentation historical proof retirement")
require(BUILD, "retired riftpp-host shell compiler surface resurfaced", "builder retired Rift++ compiler-host guard")
require(README, "RiftOS APK worker does not use `actions/upload-artifact`", "builder documentation APK artifact policy")
require(README, "managed compiler worker intentionally uses `actions/upload-artifact@v4`", "builder documentation compiler artifact policy")
require(MANAGED_WORKFLOW, "actions/upload-artifact@v4", "managed compiler artifact return lane")

print("ok - RiftOS builder contracts are internally consistent")
