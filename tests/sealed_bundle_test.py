"""Check that a sealed web app can load its declared server entry (Jac 0.37.23)."""
import hashlib
import json
import sys
import tarfile
from pathlib import Path

bundle = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/fogshot.jab")
with tarfile.open(bundle, "r:*") as archive:
    manifest = json.load(archive.extractfile("_precompiled/MANIFEST.json"))
    entry = manifest["entry"]["path"]
    record = manifest["modules"].get(entry)
    assert record, f"sealed entry has no executable module: {entry}"
    member = f'_precompiled/{manifest["python_tag"]}/{record["jir"]}'
    executable = archive.extractfile(member).read()
    assert executable, f"sealed entry is empty: {member}"
    assert hashlib.sha256(executable).hexdigest() == record["sha256"], member
print("sealed entry ok")
