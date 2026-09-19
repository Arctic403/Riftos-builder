#!/usr/bin/env bash
set -euo pipefail

PAYLOAD_DIR="${1:?usage: verify-riftclang-payload.sh <payload-dir> <abi> [llvm-version]}"
ABI="${2:?host ABI is required}"
LLVM_VERSION="${3:-23.1.1}"
PAYLOAD_DIR="$(cd "$PAYLOAD_DIR" && pwd)"

for required in python3 sha256sum readelf file find; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "missing payload verifier command: $required" >&2
    exit 1
  }
done

case "$ABI" in
  arm64-v8a)
    EXPECTED_MACHINE='AArch64'
    LIB_TRIPLE='aarch64-linux-android'
    ;;
  armeabi-v7a)
    EXPECTED_MACHINE='ARM'
    LIB_TRIPLE='arm-linux-androideabi'
    ;;
  *)
    echo "unsupported payload ABI: $ABI" >&2
    exit 2
    ;;
esac

MANIFEST="$PAYLOAD_DIR/manifest.json"
SUMS="$PAYLOAD_DIR/SHA256SUMS"
CLANG="$PAYLOAD_DIR/apk-lib/$ABI/libriftclang.so"
LLD="$PAYLOAD_DIR/apk-lib/$ABI/libriftlld.so"
DATA="$PAYLOAD_DIR/data/rift-clang-v1"

for required_path in "$MANIFEST" "$SUMS" "$CLANG" "$LLD"; do
  test -f "$required_path" || {
    echo "payload verification failed: missing $required_path" >&2
    exit 1
  }
done
test -d "$DATA/sysroot/usr/include" || { echo 'payload verification failed: sysroot headers missing' >&2; exit 1; }
test -d "$DATA/sysroot/usr/lib/$LIB_TRIPLE" || { echo "payload verification failed: sysroot libraries missing for $LIB_TRIPLE" >&2; exit 1; }
test -d "$DATA/resource/include" || { echo 'payload verification failed: Clang resource headers missing' >&2; exit 1; }

(
  cd "$PAYLOAD_DIR"
  sha256sum -c SHA256SUMS
)

grep -Fq 'manifest.json' "$SUMS" || {
  echo 'payload verification failed: manifest.json is not covered by SHA256SUMS' >&2
  exit 1
}
grep -Fq "apk-lib/$ABI/libriftclang.so" "$SUMS" || {
  echo 'payload verification failed: Clang driver is not covered by SHA256SUMS' >&2
  exit 1
}
grep -Fq "apk-lib/$ABI/libriftlld.so" "$SUMS" || {
  echo 'payload verification failed: LLD driver is not covered by SHA256SUMS' >&2
  exit 1
}

for executable in "$CLANG" "$LLD"; do
  test -x "$executable" || {
    echo "payload verification failed: executable bit missing on $executable" >&2
    exit 1
  }
  file "$executable" | grep -Fq 'ELF' || {
    echo "payload verification failed: not ELF: $executable" >&2
    exit 1
  }
  readelf -h "$executable" | grep -Fq "$EXPECTED_MACHINE" || {
    echo "payload verification failed: wrong ELF machine for $executable" >&2
    exit 1
  }
  readelf -h "$executable" | grep -Eq 'Type:[[:space:]]+(DYN|EXEC)' || {
    echo "payload verification failed: unsupported ELF type for $executable" >&2
    exit 1
  }
done

python3 - "$PAYLOAD_DIR" "$ABI" "$LLVM_VERSION" <<'PY'
import hashlib, json, os, pathlib, sys

root = pathlib.Path(sys.argv[1]).resolve()
abi = sys.argv[2]
llvm = sys.argv[3]
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

expected = {
    "format": "RIFT_CLANG_PAYLOAD_V1",
    "llvm": llvm,
    "android_api": 26,
    "host_abi": abi,
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"manifest mismatch for {key}: expected {value!r}, got {manifest.get(key)!r}")

targets = manifest.get("targets")
if targets != ["AArch64", "ARM"]:
    raise SystemExit(f"unexpected target set: {targets!r}")

commit = manifest.get("llvm_commit", "")
if not isinstance(commit, str) or len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit.lower()):
    raise SystemExit("manifest llvm_commit is not a full 40-hex commit")

files = manifest.get("files")
if not isinstance(files, list) or not files:
    raise SystemExit("manifest has no files")

seen = set()
for row in files:
    rel = row.get("path")
    size = row.get("bytes")
    if not isinstance(rel, str) or not rel or rel.startswith("/") or ".." in pathlib.PurePosixPath(rel).parts:
        raise SystemExit(f"unsafe manifest path: {rel!r}")
    if rel in seen:
        raise SystemExit(f"duplicate manifest path: {rel}")
    seen.add(rel)
    path = (root / rel).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit(f"manifest path escaped payload: {rel}")
    if not path.is_file():
        raise SystemExit(f"manifest file missing: {rel}")
    if path.stat().st_size != size:
        raise SystemExit(f"manifest size mismatch: {rel}")

actual = set()
for path in root.rglob("*"):
    if path.is_file() and path.name not in {"manifest.json", "SHA256SUMS"}:
        actual.add(path.relative_to(root).as_posix())
if actual != seen:
    missing = sorted(actual - seen)
    stale = sorted(seen - actual)
    raise SystemExit(f"manifest file set mismatch; missing={missing[:10]} stale={stale[:10]}")

sum_lines = (root / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
sum_paths = []
for line in sum_lines:
    parts = line.split(None, 1)
    if len(parts) != 2:
        raise SystemExit("malformed SHA256SUMS line")
    rel = parts[1].lstrip("*")
    if rel.startswith("./"):
        rel = rel[2:]
    if rel.startswith("/") or ".." in pathlib.PurePosixPath(rel).parts:
        raise SystemExit(f"unsafe checksum path: {rel!r}")
    sum_paths.append(rel)

expected_summed = actual | {"manifest.json"}
if set(sum_paths) != expected_summed or len(sum_paths) != len(expected_summed):
    raise SystemExit("SHA256SUMS does not cover exactly payload files plus manifest.json")

print(f"verified Rift Clang payload: {len(actual)} manifest files, ABI={abi}, LLVM={llvm}")
PY

# Non-executable compiler data must stay non-executable. Directories may carry +x for traversal.
while IFS= read -r -d '' file_path; do
  if [ -x "$file_path" ]; then
    echo "payload verification failed: executable bit set on data file: ${file_path#$PAYLOAD_DIR/}" >&2
    exit 1
  fi
done < <(find "$DATA" -type f -print0)

echo "Rift Clang payload verification passed for $ABI."
