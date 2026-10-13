#!/usr/bin/env python3
"""Builder-owned RiftOS Android-host contract. No external project fixtures.

The RiftOS repository intentionally has no Node/npm suite, bundled Core/Shell
implementation, Cloudflare relay, compiler source, project-specific proofs, or
old web runtime. These belong to separate repos. The signed host still keeps
the verified embedded graphical Shell and manual Core recovery until replaced.
"""
from pathlib import Path
import re
import sys

def fail(msg):
    raise SystemExit("RiftOS platform source validation failed: " + msg)

if len(sys.argv) != 2:
    fail("usage: validate-platform-source.py <checked-out-RiftOS>")
root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    fail("source root not found")
allowed = {"android", "docs", "README.md", "ROADMAP.md", ".gitignore",
           ".riftgit.json", ".git"}
for entry in root.iterdir():
    if entry.name not in allowed:
        fail("unexpected project-owned root entry: " + entry.name)
for name in ("android", "docs", "README.md", "ROADMAP.md",
             "docs/SOURCE_OWNERSHIP.md", "android/app/build.gradle.kts",
             "android/app/src/main/AndroidManifest.xml"):
    if not (root / name).exists():
        fail("missing platform source: " + name)

def source(relative):
    p = root / relative
    if not p.is_file():
        fail("missing platform contract source: " + relative)
    return p.read_text(encoding="utf-8")

gradle = source("android/app/build.gradle.kts")
manifest = source("android/app/src/main/AndroidManifest.xml")
host_dir = "android/app/src/main/java/com/riftos/app/"
required_sources = set(re.findall(
    r'"src/main/java/com/riftos/app/([A-Za-z][A-Za-z0-9_]*\.kt)"', gradle))
if len(required_sources) < 90:
    fail("unexpectedly small mandatory Android Kotlin source inventory")
for name in sorted(required_sources):
    if not (root / host_dir / name).is_file():
        fail("missing Gradle-listed Kotlin source: " + name)

# No source-owned project-specific runtime/CI scaffolding may sneak back.
for retired in ("external-components", "relay", "src", "scripts", "bootstrap",
                "proofs", "examples", "workspace-live", "apps", "package.json",
                "index.html", "styles.css"):
    if (root / retired).exists():
        fail("project-owned or retired root code returned: " + retired)
for retired in ('include("src/**")', 'include("workspace-live/**")',
                'RiftHeadlessJsRuntime.kt'):
    if retired in gradle:
        fail("retired APK source was repackaged: " + retired)

# Retain the current safe host boundary, verified Recovery and user control.
contracts = {
    "RiftHostComponentAbiV1.kt": [
        "interface RiftCoreComponentV1", "interface RiftCoreExternalAppConnectionsV1",
        "fun externalAppConnections(): RiftCoreExternalAppConnectionsV1"],
    "RiftHostExternalAppBinderV1.kt": [
        "fun abiVersion(): Int = 2", "fun streamFile(context: Context",
        "ParcelFileDescriptor.CREATOR", "binder.transact(IBinder.INTERFACE_TRANSACTION",
        "context.unbindService(connection)", "context.unbindService(serviceConnection)"],
    "RiftManualRecoveryStore.kt": [
        "restoreWorkingBackup", "manual"],
    "RiftProtectedDexVerifier.kt": [
        "RiftHostExternalAppBinderV1",
        "Lcom/riftos/app/RiftShellPlatformServicesV2;"],
    "RiftShellComponentAbiV1.kt": [
        "interface RiftShellPlatformServicesV1",
        "interface RiftShellPlatformServicesV2 : RiftShellPlatformServicesV1",
        "client.externalAppRequest(request)",
        "client.respondEffect(ticket, RiftRappCapabilityBroker.Result(",
        "override fun launchApkInstall(path: String): Boolean",
        'activity.packageName + ".buildapks"'],
    "RiftCoreSurfaceIpcProvider.kt": [
        'shell.external-app'],
    "RiftNativeWorkspaceApps.kt": [
        "sendFileToConnectedEditor"],
    "RiftShellActivity.kt": [
        "RiftShellCandidateSwitch"],
}
for name, markers in contracts.items():
    data = source(host_dir + name)
    for marker in markers:
        if marker not in data:
            fail(name + " missing required generic host/Recovery contract " + repr(marker))
for marker in ('android:name="androidx.core.content.FileProvider"',
               'android:grantUriPermissions="true"',
               'android.permission.REQUEST_INSTALL_PACKAGES'):
    if marker not in manifest:
        fail("Android installer security contract missing " + marker)
if '<package android:name="com.codynex.editor" />' not in manifest:
    fail("installed Codynex Editor is not visible to the Binder bridge")
print("ok - platform-only RiftOS source layout and protected Android host contracts")
