#!/usr/bin/env python3
import gzip
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

CLANG_VERSION = "21.1.8-3"
LLD_VERSION = "21.1.8-3"
NDK_VERSION = "28.2.13676358"
TOOLCHAIN_SCHEMA = "riftbuild-android-clang-toolchain/1"
ROOT_PACKAGES = (("clang", CLANG_VERSION), ("lld", LLD_VERSION))
REPOSITORIES = (
    "https://packages-cf.termux.dev/apt/termux-main",
    "https://mirror.sjtu.edu.cn/termux/apt/termux-main",
    "https://mirrors.ravidwivedi.in/termux/apt/termux-main",
)
ARCHES = {
    "arm": "armeabi-v7a",
    "aarch64": "arm64-v8a",
}
SYSTEM_LIBS = {
    "libandroid.so", "libc.so", "libdl.so", "liblog.so", "libm.so",
}
MAX_PACKAGE_COUNT = 128
MAX_DOWNLOAD_BYTES = 512 * 1024 * 1024
MAX_TOOLCHAIN_ZIP_BYTES = 512 * 1024 * 1024

def die(message):
    raise SystemExit(message)

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def fetch_bytes(urls):
    last = None
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Riftos-builder/1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read(MAX_DOWNLOAD_BYTES + 1)
            if len(data) > MAX_DOWNLOAD_BYTES:
                raise RuntimeError("download exceeded bound")
            return data, url
        except Exception as exc:
            last = exc
    raise RuntimeError("download failed: " + str(last))

def package_index(arch):
    rel = f"dists/stable/main/binary-{arch}/Packages.gz"
    data, source = fetch_bytes([base + "/" + rel for base in REPOSITORIES])
    text = gzip.decompress(data).decode("utf-8")
    records = {}
    current = {}
    key = None
    for line in text.splitlines() + [""]:
        if not line:
            if current.get("Package"):
                records.setdefault(current["Package"], []).append(current)
            current = {}
            key = None
            continue
        if line[0].isspace() and key:
            current[key] += " " + line.strip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        current[key] = value.strip()
    return records, source

def dep_names(record, index):
    raw = ",".join(x for x in (record.get("Pre-Depends", ""), record.get("Depends", "")) if x)
    if not raw:
        return []
    out = []
    for group in raw.split(","):
        chosen = None
        for alt in group.split("|"):
            name = re.split(r"\s|\(", alt.strip(), 1)[0]
            name = name.split(":", 1)[0]
            if name in index:
                chosen = name
                break
        if chosen:
            out.append(chosen)
    return out

def choose_record(index, name, version=None):
    choices = index.get(name, [])
    if version is not None:
        choices = [r for r in choices if r.get("Version") == version]
    if not choices:
        want = f"={version}" if version else ""
        die(f"Termux package missing from index: {name}{want}")
    return choices[0]

def resolve_packages(index):
    selected = {}
    queue = list(ROOT_PACKAGES)
    while queue:
        name, pinned = queue.pop(0)
        if name in selected:
            if pinned and selected[name].get("Version") != pinned:
                die(f"dependency version conflict for {name}")
            continue
        record = choose_record(index, name, pinned)
        selected[name] = record
        if len(selected) > MAX_PACKAGE_COUNT:
            die("Termux dependency closure exceeded package-count bound")
        for dep in dep_names(record, index):
            if dep not in selected:
                queue.append((dep, None))
    return selected

def download_package(record, cache_dir):
    filename = record["Filename"]
    expected = record.get("SHA256", "")
    target = cache_dir / pathlib.Path(filename).name
    if target.is_file() and expected and sha256_file(target) == expected:
        return target
    data, source = fetch_bytes([base + "/" + filename for base in REPOSITORIES])
    target.write_bytes(data)
    if expected:
        observed = sha256_file(target)
        if observed != expected:
            die(f"Termux package SHA-256 mismatch for {filename}: {observed} != {expected}")
    print(f"downloaded {filename} from {source}", file=sys.stderr)
    return target

def resolve_termux_symlink(path, root):
    path = path
    for _ in range(16):
        if not path.is_symlink():
            return path
        target = os.readlink(path)
        if os.path.isabs(target):
            prefix = "/data/data/com.termux/files/usr/"
            if not target.startswith(prefix):
                die(f"unsupported absolute Termux symlink: {path} -> {target}")
            path = root / "usr" / target[len(prefix):]
        else:
            path = (path.parent / target).resolve(strict=False)
    die(f"Termux symlink depth exceeded: {path}")

def find_binary(root, names):
    for name in names:
        candidate = root / "usr" / "bin" / name
        if candidate.exists() or candidate.is_symlink():
            resolved = resolve_termux_symlink(candidate, root)
            if resolved.is_file():
                return resolved
    die("required Termux executable missing: " + ", ".join(names))

def needed(path):
    proc = subprocess.run(
        ["readelf", "-d", str(path)],
        text=True, capture_output=True, check=True
    )
    return re.findall(r"Shared library: \[([^\]]+)\]", proc.stdout)

def library_index(root):
    out = {}
    libroot = root / "usr" / "lib"
    if not libroot.is_dir():
        return out
    for path in libroot.rglob("lib*.so*"):
        try:
            resolved = resolve_termux_symlink(path, root)
        except SystemExit:
            continue
        if resolved.is_file():
            out.setdefault(path.name, resolved)
    return out

def runtime_closure(root, roots):
    libs = library_index(root)
    selected = {}
    queue = list(roots)
    seen_elf = set()
    while queue:
        elf = pathlib.Path(queue.pop(0))
        key = str(elf)
        if key in seen_elf:
            continue
        seen_elf.add(key)
        for dep in needed(elf):
            if dep in SYSTEM_LIBS:
                continue
            if dep in selected:
                continue
            source = libs.get(dep)
            if source is None:
                die(f"unresolved Termux runtime dependency {dep} required by {elf.name}")
            if not dep.startswith("lib") or ".so" not in dep:
                die(f"runtime dependency is not Android JNI-packagable: {dep}")
            selected[dep] = source
            queue.append(source)
    return selected

def unique_name(original):
    stem = original
    if stem.startswith("lib"):
        stem = stem[3:]
    if stem.endswith(".so"):
        stem = stem[:-3]
    stem = re.sub(r"[^A-Za-z0-9_]+", "_", stem).strip("_") or "dep"
    return "libriftbuild_" + stem + ".so"

def patch_elf(path, rename_map, original_needed, soname=None):
    for old in original_needed:
        if old in rename_map:
            subprocess.run(
                ["patchelf", "--replace-needed", old, rename_map[old], str(path)],
                check=True
            )
    subprocess.run(["patchelf", "--set-rpath", "$ORIGIN", str(path)], check=True)
    if soname:
        subprocess.run(["patchelf", "--set-soname", soname, str(path)], check=True)

def prepare_host_arch(arch, abi, jni_root, work):
    index, index_source = package_index(arch)
    selected = resolve_packages(index)
    pkg_cache = work / ("pkgs-" + arch)
    extracted = work / ("root-" + arch)
    pkg_cache.mkdir(parents=True, exist_ok=True)
    extracted.mkdir(parents=True, exist_ok=True)
    package_meta = []
    for name in sorted(selected):
        record = selected[name]
        deb = download_package(record, pkg_cache)
        subprocess.run(["dpkg-deb", "-x", str(deb), str(extracted)], check=True)
        package_meta.append({
            "package": name,
            "version": record.get("Version", ""),
            "sha256": record.get("SHA256", ""),
            "filename": record.get("Filename", ""),
        })

    clang = find_binary(extracted, ("clang", "clang-21"))
    lld = find_binary(extracted, ("ld.lld", "lld"))
    closure = runtime_closure(extracted, (clang, lld))
    rename_map = {name: unique_name(name) for name in closure}
    if len(set(rename_map.values())) != len(rename_map):
        die("runtime dependency rename collision")

    out = jni_root / abi
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    compiler_out = out / "libclang_exec.so"
    linker_out = out / "libld_lld_exec.so"
    shutil.copy2(clang, compiler_out)
    shutil.copy2(lld, linker_out)
    patch_elf(compiler_out, rename_map, needed(clang))
    patch_elf(linker_out, rename_map, needed(lld))

    copied = {}
    for old_name, source in sorted(closure.items()):
        new_name = rename_map[old_name]
        target = out / new_name
        shutil.copy2(source, target)
        patch_elf(target, rename_map, needed(source), soname=new_name)
        copied[old_name] = new_name

    for executable in (compiler_out, linker_out):
        if not executable.is_file() or executable.stat().st_size <= 0:
            die(f"generated host executable missing: {executable}")
    print(f"{abi}: packaged clang/lld + {len(copied)} private runtime libraries", file=sys.stderr)
    return {
        "termuxArchitecture": arch,
        "androidAbi": abi,
        "packageIndex": index_source,
        "packages": package_meta,
        "compilerSha256": sha256_file(compiler_out),
        "linkerSha256": sha256_file(linker_out),
        "runtimeLibraries": copied,
    }

def add_tree(zf, source_root, archive_root):
    source_root = pathlib.Path(source_root)
    for path in sorted(source_root.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(source_root).as_posix()
        arc = archive_root.rstrip("/") + "/" + rel
        if path.is_symlink():
            target = path.resolve(strict=True)
            zf.writestr(arc, target.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
        else:
            zf.write(path, arc, compress_type=zipfile.ZIP_DEFLATED)

def prepare_data_archive(source_dir, metadata):
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        die("ANDROID_HOME/ANDROID_SDK_ROOT is required")
    ndk = pathlib.Path(sdk) / "ndk" / NDK_VERSION
    prebuilt = ndk / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64"
    sysroot = prebuilt / "sysroot"
    clang_root = prebuilt / "lib" / "clang"
    if not sysroot.is_dir() or not clang_root.is_dir():
        die(f"Android NDK {NDK_VERSION} sysroot/resource directory missing")
    versions = sorted([p for p in clang_root.iterdir() if p.is_dir()])
    if not versions:
        die("Android NDK clang resource directory is empty")
    resource = versions[-1]

    asset_dir = source_dir / "android" / "app" / "build" / "generated" / "riftosAssets" / "riftbuild"
    asset_dir.mkdir(parents=True, exist_ok=True)
    output = asset_dir / "android-clang-v1.zip"
    if output.exists():
        output.unlink()

    manifest = {
        "schema": TOOLCHAIN_SCHEMA,
        "version": f"clang-{CLANG_VERSION}+ndk-{NDK_VERSION}",
        "source": "builder-bundled-termux-host+android-ndk",
        "compiler": "native:libclang_exec.so",
        "sysroot": "sysroot",
        "args": [
            "--driver-mode=g++",
            "-stdlib=libc++",
            "--resource-dir=%TOOLCHAIN%/resource",
            "--ld-path=%COMPILER_DIR%/libld_lld_exec.so",
        ],
        "host": metadata,
        "ndkVersion": NDK_VERSION,
        "ndkResourceVersion": resource.name,
    }

    with zipfile.ZipFile(output, "w", allowZip64=True) as zf:
        zf.writestr(
            "toolchain.json",
            json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8"),
            compress_type=zipfile.ZIP_DEFLATED,
        )
        add_tree(zf, sysroot, "sysroot")
        add_tree(zf, resource, "resource")

    if output.stat().st_size > MAX_TOOLCHAIN_ZIP_BYTES:
        die("generated RiftBuild toolchain archive exceeds size bound")
    print(f"toolchain data archive: {output} ({output.stat().st_size} bytes)", file=sys.stderr)
    return output

def main():
    if len(sys.argv) != 2:
        die("usage: prepare-riftbuild-toolchain.py <riftos-source-dir>")
    source_dir = pathlib.Path(sys.argv[1]).resolve()
    if not (source_dir / "android" / "app" / "build.gradle.kts").is_file():
        die("RiftOS source directory is invalid")

    for command in ("dpkg-deb", "readelf", "patchelf"):
        if shutil.which(command) is None:
            die("required host command missing: " + command)

    jni_root = source_dir / "android" / "app" / "build" / "generated" / "riftosJniLibs"
    if jni_root.exists():
        shutil.rmtree(jni_root)
    jni_root.mkdir(parents=True)

    with tempfile.TemporaryDirectory(prefix="riftbuild-toolchain-") as tmp:
        work = pathlib.Path(tmp)
        metadata = {}
        for arch, abi in ARCHES.items():
            metadata[abi] = prepare_host_arch(arch, abi, jni_root, work)
        archive = prepare_data_archive(source_dir, metadata)

    result = {
        "schema": "riftos-builder-native-toolchain-v1",
        "clangVersion": CLANG_VERSION,
        "lldVersion": LLD_VERSION,
        "ndkVersion": NDK_VERSION,
        "abis": sorted(metadata),
        "asset": str(archive.relative_to(source_dir)),
        "assetSha256": sha256_file(archive),
    }
    print(json.dumps(result, sort_keys=True))

if __name__ == "__main__":
    main()
