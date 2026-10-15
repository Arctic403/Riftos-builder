#!/usr/bin/env python3
"""Test current host-only manual APK Builder contracts.

No embedded Core/Shell E0/E1/C1 milestone test assertions. Preserve exact
checkout, signing, final APK source/DEX closure, host ABI, MCP, Local Agent,
workspace and manual Recovery. External component tests live in RiftComponents.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = (ROOT / "scripts/riftos-build.sh").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/verify-riftos-apk.sh").read_text(encoding="utf-8")
SOURCE = (ROOT / "scripts/validate-platform-source.py").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/riftos-worker.yml").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")

def require(src, needle, label):
    if needle not in src:
        raise AssertionError(label + ": missing " + repr(needle))

def forbid(src, needle, label):
    if needle in src:
        raise AssertionError(label + ": retired contract returned " + repr(needle))

for marker in (
    "set -euo pipefail",
    "git rev-parse HEAD",
    "git diff --quiet HEAD",
    "git status --porcelain=v1 --untracked-files=all",
    "validate-platform-source.py",
    "RiftCoreCandidateSwitch.kt", "RiftShellCandidateSwitch.kt",
    "RiftHostExternalAppBinderV1.kt", "RiftManualRecoveryActivity.kt",
    "RiftMcpServer.kt", "RiftLocalAgentBatch.kt",
    "RiftWorkspaceRecords.kt", "RiftVolumePaths.kt",
    ':app:verifyRiftOsAndroidSources',
    ':app:validateRiftBrowserWebViewOwnership',
    "gradle -p android --stacktrace --no-build-cache :app:assembleRelease",
    '"$BUILD_TOOLS/zipalign" -p -f 4',
    '"$BUILD_TOOLS/apksigner" sign',
    '"$BUILD_TOOLS/apksigner" verify --verbose --print-certs',
    'verify-riftos-apk.sh" "$FINAL" "$SOURCE_DIR"',
    "RIFT_SIGN_STORE", "RIFT_SIGN_ALIAS",
    "RIFT_SIGN_STORE_PASS", "RIFT_SIGN_KEY_PASS",
):
    require(BUILD, marker, "signed host workflow")

for marker in (
    "host_requirements",
    "RiftMcpServer.kt",
    "RiftMcpRelayClient.kt",
    "RiftLocalAgentBatch.kt",
    "RiftVortexLocalAgent.kt",
    "RiftWorkspaceRecords.kt",
    "RiftManualRecoveryStore.kt",
    "RiftProtectedDexVerifier.kt",
    "RiftHostComponentAbiV1.kt",
    "RiftShellComponentAbiV1.kt",
    "android.permission.REQUEST_INSTALL_PACKAGES",
    "non-host repository root entries",
):
    require(SOURCE, marker, "checked-out Android platform")

for marker in (
    "require_entry", "forbid_entry", "require_dex_string",
    "require_matches_source", "resources.arsc", "FileProvider",
    "required_native_sources", "mandatory Kotlin source",
    "RiftMcpServer RiftMcpRelayClient",
    "RiftToolHost RiftLocalAgentBatch RiftVortexLocalAgent",
    "RiftWorkspaceRecords RiftWorkspaceWatcher RiftVolumePaths",
    "lib/arm64-v8a/librift_native_buffer_compiler_host.so",
    "lib/armeabi-v7a/librift_native_buffer_compiler_host.so",
    "native_assets", "SOURCE_SHA",
):
    require(VERIFY, marker, "signed APK artifact checks")

for marker in (
    "workflow_dispatch:",
    "source_ref:",
    "RIFTOS_PRIVATE_TOKEN",
    "Set up Android SDK",
    "Restore signing identity",
    "python3 worker/scripts/test-builder-contracts.py",
    "Build RiftOS APK",
):
    require(WORKFLOW, marker, "user-triggered Builder worker")

for retired in (
    "C1.4-C2-A", "C1.3-C", "C1.2-B2", "C1.1-B1",
    "E0 Core/Shell class-ownership", "Semnexis compiler/fixture tests",
    "scripts/test-e1-core-closure", "embedded graphical Shell V2 source-only",
    "npm run check", "external-components/",
):
    forbid(BUILD + SOURCE, retired, "frozen embedded/source proof gates")

for marker in ("Core", "Shell", "manual", "MCP", "Local Agent"):
    require(README, marker, "current Builder README")
if re.search(r'^\s+push:', WORKFLOW, flags=re.M):
    raise AssertionError("RiftOS worker must stay manual workflow_dispatch")
for forbidden in ("selectCoreCandidate(", "saveWorkingBackup(", "activateCore("):
    forbid(WORKFLOW + BUILD, forbidden, "CI may not select Core or Recovery")

print("PASS: host-only RiftOS Builder contracts, user-manual sign, DEX and Recovery integrity")
