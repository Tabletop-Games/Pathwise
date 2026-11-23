"""Check the slim bundle matches the release APK's symbolized native build."""
import hashlib
import sys
from zipfile import ZipFile


def library_digests(archive, prefix):
    return {
        path.removeprefix(prefix): hashlib.sha256(archive.read(path)).hexdigest()
        for path in archive.namelist()
        if path.startswith(prefix) and path.endswith(".so")
    }


with ZipFile(sys.argv[1]) as apk, ZipFile(sys.argv[2]) as bundle:
    libraries = library_digests(bundle, "base/lib/")
    assert libraries == library_digests(apk, "lib/"), "APK and AAB native binaries differ"
    for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
        for library in ("libflutter.so", "libapp.so"):
            assert f"{abi}/{library}" in libraries, f"{abi}/{library} is missing"
    metadata = bundle.namelist()
    assert any(path.endswith("/proguard.map") for path in metadata), "Missing R8 mapping"
    assert not any("com.android.tools.build.debugsymbols/" in path for path in metadata), (
        "The slim AAB must omit external native symbols"
    )
    print(f"R8 mapping present, {len(libraries)} matching native libraries, all three ABIs")
