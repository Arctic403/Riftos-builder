#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = (ROOT / "scripts" / "riftos-build.sh").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts" / "verify-riftos-apk.sh").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "riftos-worker.yml").read_text(encoding="utf-8")
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
    '"src/main/java/com/riftos/app/RiftRappHost.kt"',
    '"src/main/java/com/riftos/app/RiftRappManager.kt"',
    "private val rappManager by lazy",
    "private val bridge by lazy",
):
    require(BUILD, marker, "RiftOS native RAPP builder contract")

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

print("ok - RiftOS builder contracts are internally consistent")
