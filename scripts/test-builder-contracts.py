#!/usr/bin/env python3
"""Test current host-only manual APK Builder contracts.

No embedded Core/Shell E0/E1/C1 milestone test assertions. Preserve exact
checkout, signing, final APK source/DEX closure, host ABI, MCP, Local Agent,
workspace and manual Recovery. External component tests live in RiftComponents.
"""
from pathlib import Path
import re
import shlex
import subprocess

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
    "gradle -p android --stacktrace --no-build-cache",
    "-Pandroid.onlyEnableUnitTestForTheTestedBuildType=false",
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

# RiftOS generic JVM/JAR-D8 host changes must be enforced by all three
# Builder gates: source preflight, executed Gradle JUnit receipts and signed DEX.
for marker in (
    'docs/JVM_DEPENDENCIES.md',
    'RiftJvmDexService.kt',
    'appContext.assets.open("$ASSET_ROOT/toolchain.properties")',
    'RiftJvmClasspathPolicy.requireExact',
    'RiftJvmDexPublication.publish',
    'RiftJvmJarSupportTest.kt',
    'exactClasspathRejectsUndeclaredExtras',
    'dexPublicationRestoresPreviousOutputWhenPublishFails',
    'len(test_cases) < 20',
    'platforms/android-36/android.jar',
    'kotlin-stdlib:2.4.10',
    'finalizedBy("testReleaseUnitTest")',
):
    require(SOURCE, marker, "generic JVM host source and test gate")
for marker in (
    ':app:assembleRelease :app:testReleaseUnitTest',
    'test-results/testReleaseUnitTest',
    'RiftJvmJarSupportTest',
    'len(tests) < 20',
    'failures or skipped',
    'JVM dependency JUnit release receipt',
):
    require(BUILD, marker, "executed JVM unit test gate before signing")
for marker in (
    'toolchain.properties',
    'androidApiLevel=36',
    'androidJarSha256',
    'kotlinStdlibSha256',
    'RiftJvmDexService',
    'RiftJvmJarSupport',
    'RiftJvmClasspathPolicy',
    'RiftJvmDexPublication',
    'jvmDependencyInputsVersion',
    'Compiler classpath contains missing, duplicate or undeclared JVM JARs',
):
    require(VERIFY, marker, "final signed APK JVM dependency integrity")

# The Builder must forbid every removed implementation at source and DEX
# levels, while retaining the MCP command shell and user-controlled Recovery.
for obsolete in (
    "MainActivity", "RiftCoreRuntime", "RiftNativeDesktop",
    "RiftRappManager", "RiftShellRappHost", "RiftBrowserWindow",
):
    require(SOURCE, '"' + obsolete + '.kt"', "removed embedded source gate")
    require(VERIFY, obsolete, "signed APK embedded DEX exclusion")
require(VERIFY, "RiftNativeShell;", "MCP command shell must survive")
require(SOURCE, 'const val TOOL_INVOKE = "tool.invoke"', "RAPP tool invoke host ABI source gate")
require(VERIFY, "generic RAPP Core-owned tool invocation ABI constant", "RAPP tool invoke final DEX gate")
require(SOURCE, 'com.riftos.tool.BIND_V1', "generic Android tool visibility source gate")
require(VERIFY, 'com.riftos.tool.BIND_V1', "generic Android tool visibility signed APK gate")
# The installer moved to retained Android Shell V2 platform services.
# Require its DEX class and stable Builds-root literal, plus the actual
# source-level path, symlink, package-identity, and FileProvider gates.
for marker in (
    "Lcom/riftos/app/RiftShellPlatformServicesAdapter;",
    "/D:/Builds/",
):
    require(VERIFY, marker, "external Shell Android installer final-DEX gate")
for marker in (
    'display.startsWith("/D:/Builds/")',
    "file.path.startsWith(builds.path",
    "Files.isSymbolicLink",
    "getPackageArchiveInfo",
    "FileProvider.getUriForFile",
):
    require(SOURCE, marker, "external Shell Android installer source gate")
forbid(VERIFY, "APK installation is limited to D:/Builds artifacts",
       "retired embedded installer smoke-test marker")
require(SOURCE, "embedded fallback still reachable", "external-only fail-closed")
require(SOURCE, "retired embedded/proof Activity", "obsolete manifest source gate")

for marker in ("Core", "Shell", "manual", "MCP", "Local Agent"):
    require(README, marker, "current Builder README")
if re.search(r'^\s+push:', WORKFLOW, flags=re.M):
    raise AssertionError("RiftOS worker must stay manual workflow_dispatch")
for forbidden in ("selectCoreCandidate(", "saveWorkingBackup(", "activateCore("):
    forbid(WORKFLOW + BUILD, forbidden, "CI may not select Core or Recovery")

# Execute the exact SHA-key guard extracted from the actual signed-APK verifier.
# This catches shell variable escaping bugs that marker-only tests cannot catch.
begin = "for sha_key in androidJarSha256 kotlinStdlibSha256; do"
if VERIFY.count(begin) != 1:
    raise AssertionError("signed APK toolchain digest guard is missing or duplicated")
digest_guard = begin + VERIFY.split(begin, 1)[1].split("\ndone", 1)[0] + "\ndone"
if not digest_guard.endswith("\ndone"):
    raise AssertionError("signed APK toolchain digest guard is malformed")
valid_metadata = "androidApiLevel=36\nandroidJarSha256=" + "a" * 64 + "\nkotlinStdlibSha256=" + "b" * 64
fixtures = (
    ("valid", valid_metadata, True),
    ("missing", valid_metadata.replace("androidJarSha256=" + "a" * 64 + "\n", ""), False),
    ("malformed", valid_metadata.replace("a" * 64, "not-a-hash"), False),
    ("duplicate", valid_metadata + "\nandroidJarSha256=" + "a" * 64, False),
)
for name, metadata, should_pass in fixtures:
    script = "set -euo pipefail\ntoolchain_metadata=" + shlex.quote(metadata) + "\n" + digest_guard + "\n"
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=10)
    if (result.returncode == 0) != should_pass:
        raise AssertionError(
            "signed APK toolchain digest guard case " + name +
            " returned " + str(result.returncode) + ": " + result.stderr.strip()
        )

print("PASS: host-only RiftOS Builder contracts, user-manual sign, DEX and Recovery integrity")