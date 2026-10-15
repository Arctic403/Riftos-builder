#!/usr/bin/env python3
"""Host-only RiftOS release source validation.

Validate the Android APK envelope and selected external component transport,
not frozen embedded Core/Shell milestone implementations or their retired tests.
The user explicitly controls build/install, component selection and Recovery.
"""
from pathlib import Path
import re
import sys

def fail(message):
    raise SystemExit("RiftOS host source validation failed: " + message)

if len(sys.argv) != 2:
    fail("usage: validate-platform-source.py <RiftOS-checkout>")
root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    fail("missing RiftOS checkout")
allowed = {"android", "docs", "README.md", ".gitignore", ".riftgit.json", ".git"}
unexpected = sorted(p.name for p in root.iterdir() if p.name not in allowed)
if unexpected:
    fail("non-host repository root entries: " + ", ".join(unexpected))

required_docs = (
    "README.md", "docs/README.md", "docs/ARCHITECTURE.md",
    "docs/EXTERNAL_COMPONENTS.md", "docs/OPERATING_SERVICES.md",
    "docs/PLATFORM_CAPABILITIES.md", "docs/HOST_VALIDATION.md",
    "docs/SOURCE_OWNERSHIP.md"
)
for rel in required_docs:
    if not (root / rel).is_file():
        fail("missing current host documentation: " + rel)

def read(relative):
    path = root / relative
    if not path.is_file():
        fail("missing host source: " + relative)
    return path.read_text(encoding="utf-8")

prefix = "android/app/src/main/java/com/riftos/app/"
gradle = read("android/app/build.gradle.kts")
manifest = read("android/app/src/main/AndroidManifest.xml")
android_sources = set(re.findall(
    r'"src/main/java/com/riftos/app/([A-Za-z][A-Za-z0-9_]*\.kt)"', gradle
))
if len(android_sources) < 20:
    fail("missing mandatory Gradle Android source inventory")
for name in sorted(android_sources):
    if not (root / prefix / name).is_file():
        fail("Gradle mandatory source missing: " + name)

# Only APK-owned host, MCP, Local Agent, workspace, loader/recovery and
# generic transport are qualified. Frozen embedded source may remain in Gradle.
host_requirements = {
    "RiftCoreApplication.kt": ("class RiftCoreApplication",),
    "RiftShellActivity.kt": ("class RiftShellActivity", "RiftShellCandidateSwitch"),
    "RiftHostComponentAbiV1.kt": ("interface RiftCoreComponentV1",),
    "RiftShellComponentAbiV1.kt": (
        "interface RiftShellGraphicalComponentV1",
        "interface RiftShellPlatformServicesV1",
        "interface RiftShellPlatformServicesV2",
    ),
    "RiftCoreCandidateSwitch.kt": ("selectAtBoot",),
    "RiftShellCandidateSwitch.kt": ("selectAtBoot",),
    "RiftProtectedComponentManifest.kt": ("protected-component",),
    "RiftProtectedDexVerifier.kt": ("RiftHostExternalAppBinderV1",),
    "RiftProtectedComponentInstaller.kt": ("object RiftProtectedComponentInstaller",),
    "RiftProtectedRevisionRecovery.kt": ("object ",),
    "RiftManualRecoveryStore.kt": ("restoreWorkingBackup",),
    "RiftManualRecoveryActivity.kt": ("class RiftManualRecoveryActivity",),
    "RiftHostExternalAppBinderV1.kt": (
        "fun streamFile(context: Context", "ParcelFileDescriptor.CREATOR",
    ),
    "RiftCoreSurfaceIpcProvider.kt": ("shell.external-app",),
    "RiftMcpServer.kt": ("class RiftMcpServer",),
    "RiftMcpRelayClient.kt": ("class RiftMcpRelayClient",),
    "RiftMcpOperationJournal.kt": ("class RiftMcpOperationJournal",),
    "RiftToolHost.kt": ("class RiftToolHost",),
    "RiftVortexLocalAgent.kt": ("AccessibilityService",),
    "RiftLocalAgentBatch.kt": ("object RiftLocalAgentBatch", "MAX_STEPS = 16"),
    "RiftWorkspaceRecords.kt": ("class RiftWorkspaceRecords",),
    "RiftWorkspaceWatcher.kt": ("class RiftWorkspaceWatcher",),
    "RiftVolumePaths.kt": ("object RiftVolumePaths",),
    "RiftNativeGit.kt": ("git",),
    "RiftRappCapabilityBroker.kt": ("class RiftRappCapabilityBroker",),
}
for file, markers in host_requirements.items():
    if file not in android_sources:
        fail("host dependency not in Gradle source inventory: " + file)
    source = read(prefix + file)
    for marker in markers:
        if marker not in source:
            fail("missing host contract " + file + ": " + repr(marker))

for marker in (
    'android:name=".RiftCoreApplication"',
    'android:name=".RiftShellActivity"',
    'android:name=".RiftManualRecoveryActivity"',
    'android:name=".RiftMcpActivity"',
    'android:name=".RiftVortexAccessibilityService"',
    'android:name=".RiftCoreSurfaceIpcProvider"',
    'android:name="androidx.core.content.FileProvider"',
    'android:grantUriPermissions="true"',
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android:usesCleartextTraffic="false"',
):
    if marker not in manifest:
        fail("missing Android manifest security / platform contract: " + marker)

for marker in (
    'namespace = "com.riftos.app"', 'applicationId = "com.riftos.app"',
    'abiFilters += listOf("arm64-v8a", "armeabi-v7a")',
    "verifyRiftOsAndroidSources",
    "validateRiftBrowserWebViewOwnership",
):
    if marker not in gradle:
        fail("missing Android build contract: " + marker)

for retired in (
    "scripts", "package.json", "external-components", "relay",
    "workspace-live", "proofs", "bootstrap", "examples",
):
    if (root / retired).exists():
        fail("obsolete non-host root returned: " + retired)
if (root / prefix / "RiftHeadlessJsRuntime.kt").exists():
    fail("retired headless JavaScript desktop returned")

print("PASS: RiftOS checked-out APK host, MCP, Local Agent, workspace, external component interfaces and manual Recovery")
