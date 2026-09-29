#!/usr/bin/env python3
import importlib.util
import pathlib
import tempfile


SCRIPT = pathlib.Path(__file__).with_name("prepare-riftbuild-toolchain.py")
SPEC = importlib.util.spec_from_file_location("riftbuild_toolchain", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def write(path, data=b"x"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def expect_system_exit(fn, contains):
    try:
        fn()
    except SystemExit as exc:
        message = str(exc)
        assert contains in message, message
        return
    raise AssertionError("expected SystemExit")


with tempfile.TemporaryDirectory(prefix="riftbuild-toolchain-layout-test-") as tmp:
    root = pathlib.Path(tmp) / "packaged"
    prefix = root / "data" / "data" / "com.termux" / "files" / "usr"
    clang21 = write(prefix / "bin" / "clang-21")
    (prefix / "bin" / "clang").symlink_to("clang-21")
    lib = write(prefix / "lib" / "libfixture.so")
    (prefix / "lib" / "libfixture-absolute.so").symlink_to(
        "/data/data/com.termux/files/usr/lib/libfixture.so"
    )

    assert MODULE.termux_prefix(root) == prefix
    assert MODULE.find_binary(root, ("clang", "clang-21")) == clang21
    assert MODULE.resolve_termux_symlink(
        prefix / "lib" / "libfixture-absolute.so", root
    ) == lib
    libraries = MODULE.library_index(root)
    assert libraries["libfixture.so"] == lib
    assert libraries["libfixture-absolute.so"] == lib

    flat_root = pathlib.Path(tmp) / "flat"
    flat_prefix = flat_root / "usr"
    flat_clang = write(flat_prefix / "bin" / "clang")
    write(flat_prefix / "lib" / "libflat.so")
    assert MODULE.termux_prefix(flat_root) == flat_prefix
    assert MODULE.find_binary(flat_root, ("clang",)) == flat_clang

    ambiguous = pathlib.Path(tmp) / "ambiguous"
    write(ambiguous / "usr" / "bin" / "clang")
    write(
        ambiguous / "data" / "data" / "com.termux" / "files" / "usr" /
        "bin" / "clang"
    )
    expect_system_exit(
        lambda: MODULE.termux_prefix(ambiguous),
        "ambiguous Termux prefix layout",
    )

    escaping = pathlib.Path(tmp) / "escaping"
    escaping_prefix = escaping / "data" / "data" / "com.termux" / "files" / "usr"
    write(escaping / "outside")
    (escaping_prefix / "bin").mkdir(parents=True, exist_ok=True)
    (escaping_prefix / "bin" / "escape").symlink_to("../../../../../../../outside")
    expect_system_exit(
        lambda: MODULE.resolve_termux_symlink(
            escaping_prefix / "bin" / "escape", escaping
        ),
        "Termux symlink escapes extracted prefix",
    )

print("RiftBuild Termux package-layout regression PASS")
