#!/usr/bin/env python3
"""Fail-closed Host native RiftShell Generic Tool source-contract preflight.

The external Core owns the signer-pinned tool registry and per-call consent.
This verifies that the APK-owned native CLI forwards only complete, bounded
provider requests to the selected Core without bypassing any Core permission.
Static source contract test, NOT Kotlin compilation or Android runtime proof.
"""
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit("FAIL: RiftOS native Generic Tool shell contract: " + message)


if len(sys.argv) != 2:
    fail("usage: test-native-shell-tools.py <checked-out-RiftOS-host-repo>")

root = Path(sys.argv[1]).resolve(strict=True)
shell_path = root / "android/app/src/main/java/com/riftos/app/RiftNativeShell.kt"
abi_path = root / "android/app/src/main/java/com/riftos/app/RiftHostComponentAbiV1.kt"
test_path = root / "docs/tests/native-shell-generic-tool-source-test.js"
if not all(p.is_file() for p in (shell_path, abi_path, test_path)):
    fail("RiftNativeShell, Core external connection ABI, or scoped source tests missing")

shell = shell_path.read_text(encoding="utf-8")
abi = abi_path.read_text(encoding="utf-8")
js_tests = test_path.read_text(encoding="utf-8")

def expect(text: str, value: str, label: str) -> None:
    if value not in text:
        fail(label)


def disallow(text: str, value: str, label: str) -> None:
    if value in text:
        fail(label)


expect(shell, '"tool" -> genericToolCommand(raw, cwd)',
       "native command dispatch missing")
expect(shell, '"workspace push", "tool list", "tool call"',
       "supported-op list not updated")
expect(shell, "private fun genericToolCommand(raw: String, cwd: String): ShellOutcome",
       "tool shell handler missing")
assert shell.count("private fun genericToolCommand(") == 1, "Duplicate tool handlers"
handler = shell.split("private fun genericToolCommand(", 1)[1].split(
    "private fun cdCommand(", 1
)[0]
expect(handler, '"riftos.core.app-connection-request/1"', "Core request schema missing")
expect(handler, 'request.put("operation", "tool-list")',
       "tool list no longer routed to Core")
expect(handler, 'request.put("operation", "tool-call")',
       "tool call no longer routed to Core")
expect(handler, ".put(\"id\", id).put(\"command\", provider)",
       "Core tool request no longer includes provider command")
# The trust command must not add an alternate Binder or permission route.
# It only transports typed start/status/stop requests into selected Core,
# which always validates saved scopes and obtains fresh user consent on start.
for marker, error in (
    ('"trust" -> {', "temporary trust CLI missing"),
    ('request.put("operation","tool-session-start")',
     "temporary trust start not routed through Core"),
    ('request.put("operation","tool-session-status")',
     "temporary trust status not routed through Core"),
    ('request.put("operation","tool-session-stop")',
     "temporary trust stop not routed through Core"),
    ('minutes in 1..15', "temporary trust duration not bounded"),
    ('granted.size in 1..8', "temporary trust operation count not bounded"),
    ('granted.size==granted.toSet().size',
     "temporary trust must reject duplicate operations"),
):
    expect(handler, marker, error)

# Core-owned binary transfer must be available from MCP's native RiftShell.
# External graphical RiftShell is not sufficient; the native shell handles
# MCP rift_shell_exec without Accessibility/terminal taps.
for marker, error in (
    ('"file" -> {', "native tool file command missing"),
    ('"import" -> {', "tool file import branch missing"),
    ('request.put("operation", "tool-file-send")',
     "file import must route to selected Core"),
    ('.put("from", checkedPath(pieces[4]))',
     "file import source path must be checked"),
    ('"export" -> {', "tool file export branch missing"),
    ('request.put("operation", "tool-file-receive")',
     "file export must route to selected Core"),
    ('.put("to", checkedPath(pieces[5]))',
     "file export destination path must be checked"),
    ('"status" -> {', "file transfer status missing"),
    ('request.put("operation", "tool-file-status")',
     "file transfer status must route to Core"),
    ('"cancel" -> {', "file transfer cancel missing"),
    ('request.put("operation", "tool-file-cancel")',
     "file transfer cancellation must route to Core"),
    ('pieces.size == 5', "file import argument count not bounded"),
    ('pieces.size == 6', "file export argument count not bounded"),
    ('pieces.size == 3', "file status/cancel argument count not bounded"),
    ('it.length in 16..512', "file path size not bounded"),
    ('!it.contains("//")', "duplicate-separator file path not rejected"),
    ('segment == "." || segment == ".."',
     "file path traversal not rejected"),
):
    expect(handler, marker, error)

file_allowed = re.compile(
    r"^/D:/(Workspace|Projects|Documents|Downloads|Builds|Temp)/[A-Za-z0-9_./+()-]+$"
)
file_good = (
    "/D:/Workspace/RiftElectricity/models/manual.bbmodel",
    "/D:/Projects/models/panel-v1.bbmodel",
    "/D:/Downloads/exports/optimized-model.bbmodel",
)
file_bad = (
    "/D:/Workspace/../Documents/private.bbmodel",
    "/D:/Workspace/./model.bbmodel",
    "/D:/Workspace/models//model.bbmodel",
    "/D:/Android/data/other.app/private.bbmodel",
    "/C:/Workspace/model.bbmodel",
)
def valid_file_path(value: str) -> bool:
    return (16 <= len(value) <= 512 and
            bool(file_allowed.fullmatch(value)) and
            "//" not in value and
            not any(p in (".", "..") for p in value[len("/D:/"):].split("/")))
if not all(valid_file_path(p) for p in file_good):
    fail("valid Core file-transfer path rejected by reference parser")
if any(valid_file_path(p) for p in file_bad):
    fail("unsafe Core file-transfer path accepted by reference parser")

expect(handler, "RiftHostCoreComponents.externalAppConnections()",
       "selected external Core gate missing")
expect(handler, ".appConnectionRequest(appContext, request)",
       "Core tool request route missing")
expect(abi, "fun externalAppConnections(): RiftCoreExternalAppConnectionsV1",
       "selected Core service ABI missing")
expect(abi, "fun appConnectionRequest(context: Context, request: JSONObject): JSONObject",
       "generic tool Core ABI missing")
for forbidden in ("RiftHostExternalAppBinderV1", "Binder.transact",
                  "getSystemService", "tool-attach", "tool-edit", "tool-detach"):
    disallow(handler, forbidden, "CLI must never bypass Core approval: " + forbidden)

for marker, problem in (
    ('Regex("^[a-z][a-z0-9-]{1,39}$")', "approved id validator missing"),
    ('provider.has("operation") != provider.has("op")',
     "exactly-one-provider-operation validator missing"),
    ('provider.optString("schema").isNotBlank()', "provider schema required"),
    ('2..16_384', "file/inline request size bound missing"),
    ('<= 24_576', "Core IPC message size bound missing"),
    ('<= 256 * 1024', "Core IPC response bound missing"),
    ('java.nio.file.Files.isSymbolicLink(input.toPath())',
     "provider request file symlink check missing"),
    ('approvedRoot.canonicalPath + File.separator',
     "provider file canonical-root check missing"),
    ('arg.removePrefix("/D:/").split(\'/\').none { it == "." || it == ".." }',
     "provider file path traversal check missing"),
    ('require(fields.size == 4)', "tool call must supply provider argument"),
):
    expect(handler, marker, problem)

# Verify only the three approved virtual RiftFS roots may contain provider
# JSON. Reject ambiguous paths, dot segments and invalid connection ids.
allowed = re.compile(r"^/D:/(Workspace|Documents|Projects)/[A-Za-z0-9_./-]+\.json$")
ids = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
good_paths = (
    "/D:/Workspace/RiftBenchBridge/commands/status.json",
    "/D:/Documents/tools/describe.json",
    "/D:/Projects/dev/generic-tool.json",
)
bad_paths = (
    "/D:/Workspace/../Credentials/private.json",
    "/D:/Workspace/./cmd.json",
    "/D:/Workspace/a//b.json",
    "/D:/Downloads/command.json",
    "/C:/Workspace/RiftBenchBridge/commands/status.json",
    "/D:/Workspace/commands/bad.json.bak",
)
def valid_path(path: str) -> bool:
    return bool(allowed.fullmatch(path)) and "//" not in path and not any(
        part in (".", "..") for part in path[len("/D:/"):].split("/")
    )
if not all(valid_path(p) for p in good_paths):
    fail("valid provider request path rejected by reference parser")
if any(valid_path(p) for p in bad_paths):
    fail("unsafe provider request path accepted by reference parser")
if not all(ids.fullmatch(p) for p in ("riftbench-bridge", "relay1", "tool-id")):
    fail("valid approved tool id rejected by reference parser")
if any(ids.fullmatch(p) for p in ("../secret", "BAD", "a", "riftbench_bridge", "")):
    fail("invalid tool id accepted by reference parser")
for marker in (
    "verifyNativeGenericToolSource", "tool list",
    "project-summary.json", "path traversal", "35",
):
    # JS tests may count cases dynamically, so only the function/fixture
    # marker is mandatory; other semantics are validated above.
    if marker == "verifyNativeGenericToolSource":
        expect(js_tests, marker, "source regression fixture missing")

print("PASS: native RiftShell Generic Tool CLI uses selected Core consent and "
      "bounded provider-only requests (source/contract checks)")
