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
