#!/usr/bin/env python3
"""RiftOS Builder contract tests after project-repo separation.

Protect the signed APK, private source SHA, Recovery, Core Binder ABI, and
Gradle build steps; do NOT require language proofs/Node tests/independent
Core source inside RiftOS-main. Runner invokes this before Android build.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = (ROOT / "scripts/riftos-build.sh").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/verify-riftos-apk.sh").read_text(encoding="utf-8")
SOURCE = (ROOT / "scripts/validate-platform-source.py").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/riftos-worker.yml").read_text(encoding="utf-8")

def require(text, marker, name):
    if marker not in text:
        raise AssertionError(name + ": missing " + repr(marker))

def forbid(text, marker, name):
    if marker in text:
        raise AssertionError(name + ": must not contain " + repr(marker))

for marker in (
    "set -euo pipefail", 'git rev-parse HEAD', 'git diff --quiet HEAD',
    'git status --porcelain=v1 --untracked-files=all',
    'python3 "$SCRIPT_DIR/validate-platform-source.py" "$SOURCE_DIR"',
    ':app:verifyRiftOsAndroidSources',
    ':app:validateRiftBrowserWebViewOwnership',
    'gradle -p android --stacktrace --no-build-cache :app:assembleRelease',
    '"$BUILD_TOOLS/zipalign" -p -f 4', '"$BUILD_TOOLS/apksigner" sign',
    '"$BUILD_TOOLS/apksigner" verify --verbose --print-certs',
    'verify-riftos-apk.sh" "$FINAL" "$SOURCE_DIR"',
    "RIFT_SIGN_STORE", "RIFT_SIGN_ALIAS",
    "RIFT_SIGN_STORE_PASS", "RIFT_SIGN_KEY_PASS",
    'RiftHostExternalAppBinderV1.kt', 'fun streamFile(context: Context',
    'ParcelFileDescriptor.CREATOR',
    "RiftManualRecoveryStore.kt", "RiftProtectedDexVerifier.kt",
    "RiftCoreSurfaceIpcProvider.kt",
):
    require(BUILD, marker, "safe host build")

# Signed-host Shell V2 is strictly additive to existing V1 candidates.
for marker in (
    'interface RiftShellPlatformServicesV2 : RiftShellPlatformServicesV1',
    'fun externalAppRequest(request: JSONObject): JSONObject',
    'fun respondEffect(ticket: Long, response: JSONObject): Boolean',
    'fun launchApkInstall(path: String): Boolean',
    'Lcom/riftos/app/RiftShellPlatformServicesV2;',
    'RiftShellPlatformServicesAdapter(externalCore, this)',
):
    require(BUILD, marker, "Shell V2 host compatibility gate")
for marker in (
    'RiftShellComponentAbiV1.kt',
    'interface RiftShellPlatformServicesV2 : RiftShellPlatformServicesV1',
    'Lcom/riftos/app/RiftShellPlatformServicesV2;',
):
    require(SOURCE, marker, "Shell V2 platform source verification")

for marker in (
    "npm run check", "scripts/test-", "external-components/",
    'require("./package.json")', "semnexis-selfhost-frontend-v18.snx",
):
    forbid(BUILD, marker, "external project dependency")

for marker in (
    "scripts", "external-components", "relay", "workspace-live",
    "proofs", "bootstrap", "package.json", 're.findall(',
    'required_sources', 'RiftManualRecoveryStore.kt',
    'RiftHostExternalAppBinderV1.kt',
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'RiftShellCandidateSwitch',
    'unexpected project-owned root entry',
):
    require(SOURCE, marker, "Builder-owned platform validation")

for marker in (
    'Riftos-builder', "source_sha", "checkout@v7",
    "RIFTOS_PRIVATE_TOKEN", "Set up Android SDK",
    "Restore signing identity", "python3 worker/scripts/test-builder-contracts.py",
    "Build RiftOS APK",
):
    require(WORKFLOW, marker, "isolated private build worker")

for marker in (
    "set -euo pipefail", "require_entry", "forbid_entry",
    "require_dex_string", "forbid_dex_string",
    "require_matches_source", "resources.arsc", "FileProvider",
    "classes", "assets/www",
):
    require(VERIFY, marker, "signed APK smoke verifier")

# No project proof required to approve a host binary and no automatic
# Core candidate selection/Recovery promotion in the worker.
for marker in ("restoreWorkingBackup", "manualRecoveryOnly"):
    require(BUILD + SOURCE, marker, "Recovery fail-safe")
for marker in ("selectCoreCandidate(", "saveWorkingBackup(", "activateCore("):
    forbid(WORKFLOW, marker, "unapproved release promotion")
if not re.search(r'gradle -p android.*:app:assembleRelease', BUILD):
    raise AssertionError("release build step missing")
print("ok - isolated RiftOS Builder contracts match platform-only repo")
