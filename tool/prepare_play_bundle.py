"""Write a separately signed Play upload without native debug metadata.

Flutter's standard build checks that both Flutter and Dart symbols were
extracted into metadata. Preserve that original build and its symbol zip.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
from zipfile import ZipFile


def main():
    original, output = map(Path, sys.argv[1:])
    if original.resolve() == output.resolve() or output.exists():
        sys.exit("Choose a new output path for the slim, signed bundle.")
    required = ("KEYSTORE", "STORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD")
    signing = {name: os.environ.get(f"PATHWISE_{name}") for name in required}
    if not all(signing.values()):
        sys.exit("Set the four PATHWISE signing variables documented in setup.md.")

    native_metadata = "BUNDLE-METADATA/com.android.tools.build.debugsymbols/"
    signature = re.compile(r"META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC))$", re.I)
    with ZipFile(original) as source:
        if not any(entry.startswith(native_metadata) for entry in source.namelist()):
            sys.exit("The original Flutter AAB does not contain native symbols.")
        with ZipFile(output, "x") as destination:
            for entry in source.infolist():
                if not entry.filename.startswith(native_metadata) and not signature.fullmatch(entry.filename):
                    destination.writestr(entry, source.read(entry))

    try:
        subprocess.run([
            "jarsigner", "-keystore", signing["KEYSTORE"],
            "-storepass:env", "PATHWISE_STORE_PASSWORD",
            "-keypass:env", "PATHWISE_KEY_PASSWORD",
            str(output), signing["KEY_ALIAS"],
        ], check=True)
    except (OSError, subprocess.CalledProcessError):
        output.unlink()
        raise


if __name__ == "__main__":
    main()
