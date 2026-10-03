"""Validate packaging for a physical iPhone; not a signature/install verification."""
import plistlib
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None, "Corrupted IPA"
    root = "Payload/CameraLog.app/"
    info = plistlib.loads(archive.read(root + "Info.plist"))
    executable = info["CFBundleExecutable"]
    assert root + executable in archive.namelist(), "Missing executable"
    assert info["CFBundlePackageType"] == "APPL", "Not an application bundle"
    assert "iPhoneOS" in info["CFBundleSupportedPlatforms"], "This is a simulator build"
    assert 1 in info["UIDeviceFamily"], "iPhone is not a supported device family"
    assert info["CFBundleIdentifier"], "Missing bundle identifier"
    assert int(info["MinimumOSVersion"].split(".")[0]) == 17, "Unexpected minimum iOS version"
print(f"PASS: {path.name}, physical iPhone, iOS {info['MinimumOSVersion']}+, {path.stat().st_size} bytes.")
print("Unsigned: install/re-sign using your own Apple account in Sideloadly on Windows.")
