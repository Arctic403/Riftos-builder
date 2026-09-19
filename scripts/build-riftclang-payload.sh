#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLVM_VERSION="${LLVM_VERSION:-23.1.1}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is required}"
ABI="${1:-arm64-v8a}"
OUT_DIR="${2:-$PWD/out/riftclang-$ABI}"
API=26

for required in git cmake ninja python3 file readelf sha256sum tar gzip; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "missing Rift Clang builder command: $required" >&2
    exit 1
  }
done

case "$ABI" in
  arm64-v8a)
    HOST_TRIPLE="aarch64-linux-android$API"
    LIB_TRIPLE="aarch64-linux-android"
    ;;
  armeabi-v7a)
    HOST_TRIPLE="armv7a-linux-androideabi$API"
    LIB_TRIPLE="arm-linux-androideabi"
    ;;
  *)
    echo "unsupported host ABI: $ABI" >&2
    exit 2
    ;;
esac

ROOT="$PWD/.riftclang-work/$ABI"
SRC="$ROOT/llvm-project"
HOST_BUILD="$ROOT/host-build"
TARGET_BUILD="$ROOT/target-build"
PAYLOAD="$OUT_DIR/payload"
APK_LIB="$PAYLOAD/apk-lib/$ABI"
DATA="$PAYLOAD/data/rift-clang-v1"
LOG="$OUT_DIR/build.log"

rm -rf "$ROOT" "$OUT_DIR"
mkdir -p "$ROOT" "$APK_LIB" "$DATA" "$(dirname "$LOG")"

exec > >(tee "$LOG") 2>&1

echo "LLVM_VERSION=$LLVM_VERSION"
echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "ABI=$ABI"
echo "HOST_TRIPLE=$HOST_TRIPLE"

git clone --depth 1 --branch "llvmorg-$LLVM_VERSION" https://github.com/llvm/llvm-project.git "$SRC"
LLVM_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
test "${#LLVM_COMMIT}" -eq 40 || {
  echo "Could not resolve full LLVM commit." >&2
  exit 1
}
echo "LLVM_COMMIT=$LLVM_COMMIT"

cmake -S "$SRC/llvm" -B "$HOST_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF

cmake --build "$HOST_BUILD" --target llvm-tblgen clang-tblgen -- -j2

cmake -S "$SRC/llvm" -B "$TARGET_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="android-$API" \
  -DANDROID_STL=c++_static \
  -DLLVM_HOST_TRIPLE="$HOST_TRIPLE" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$HOST_TRIPLE" \
  -DLLVM_NATIVE_TOOL_DIR="$HOST_BUILD/bin" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF \
  -DLLVM_LINK_LLVM_DYLIB=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF

cmake --build "$TARGET_BUILD" --target clang lld -- -j2

STRIP="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
test -x "$TARGET_BUILD/bin/clang"
test -x "$TARGET_BUILD/bin/lld"
test -x "$STRIP"

cp "$TARGET_BUILD/bin/clang" "$APK_LIB/libriftclang.so"
cp "$TARGET_BUILD/bin/lld" "$APK_LIB/libriftlld.so"
"$STRIP" --strip-unneeded "$APK_LIB/libriftclang.so"
"$STRIP" --strip-unneeded "$APK_LIB/libriftlld.so"
chmod 0755 "$APK_LIB/libriftclang.so" "$APK_LIB/libriftlld.so"

mkdir -p "$DATA/sysroot/usr" "$DATA/resource"

cp -a "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" \
  "$DATA/sysroot/usr/include"
mkdir -p "$DATA/sysroot/usr/lib"
cp -a "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$LIB_TRIPLE" \
  "$DATA/sysroot/usr/lib/$LIB_TRIPLE"

RESOURCE_INCLUDE="$(find "$TARGET_BUILD/lib/clang" -mindepth 2 -maxdepth 2 -type d -name include | sort -V | tail -n 1)"
test -n "$RESOURCE_INCLUDE" && test -d "$RESOURCE_INCLUDE"
cp -a "$RESOURCE_INCLUDE" "$DATA/resource/include"

file "$APK_LIB/libriftclang.so"
file "$APK_LIB/libriftlld.so"

case "$ABI" in
  arm64-v8a)
    readelf -h "$APK_LIB/libriftclang.so" | grep -q 'AArch64'
    readelf -h "$APK_LIB/libriftlld.so" | grep -q 'AArch64'
    ;;
  armeabi-v7a)
    readelf -h "$APK_LIB/libriftclang.so" | grep -Eq 'ARM'
    readelf -h "$APK_LIB/libriftlld.so" | grep -Eq 'ARM'
    ;;
esac

python3 - "$PAYLOAD" "$LLVM_VERSION" "$LLVM_COMMIT" "$ABI" "$HOST_TRIPLE" <<'PY'
import json, os, sys
root, llvm_version, llvm_commit, abi, triple = sys.argv[1:]
files = []
for base, dirs, names in os.walk(root):
    dirs.sort()
    for name in sorted(names):
        if name in {"manifest.json", "SHA256SUMS"}:
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        files.append({"path": rel, "bytes": os.path.getsize(path)})
manifest = {
    "format": "RIFT_CLANG_PAYLOAD_V1",
    "llvm": llvm_version,
    "llvm_commit": llvm_commit,
    "android_ndk": "30.0.16248370",
    "android_api": 26,
    "host_abi": abi,
    "host_triple": triple,
    "targets": ["AArch64", "ARM"],
    "files": files,
}
with open(os.path.join(root, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
PY

(
  cd "$PAYLOAD"
  find . -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum > SHA256SUMS
)

bash "$SCRIPT_DIR/verify-riftclang-payload.sh" "$PAYLOAD" "$ABI" "$LLVM_VERSION"

ARCHIVE="$OUT_DIR/rift-clang-v1-$ABI.tar.gz"
tar --sort=name \
  --mtime='UTC 2020-01-01' \
  --owner=0 --group=0 --numeric-owner \
  -C "$PAYLOAD" -cf - . |
  gzip -n > "$ARCHIVE"

sha256sum "$ARCHIVE" | tee "$OUT_DIR/payload.sha256"

echo "Rift Clang payload staged at $OUT_DIR"
