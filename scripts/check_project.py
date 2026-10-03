"""Structural verification only; this does not compile or type-check Swift."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = (root / "CameraLog.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
definitions = re.findall(r"^\s*([A-F0-9]{24}) = \{", project, re.M)
assert len(definitions) == len(set(definitions)), "Duplicate object ID"
references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
assert references == set(definitions), "Unresolved object reference"
paths = re.findall(r'path = "([^"]+\.swift)";', project)
actual = sorted(p.relative_to(root).as_posix() for folder in ("CameraLog", "CameraLogTests")
                for p in (root / folder).rglob("*.swift"))
assert sorted(paths) == actual, "Sources missing from Xcode project"
for path in paths:
    assert (root / path).is_file(), path
builds = re.findall(r"isa = PBXBuildFile; fileRef = ([A-F0-9]{24});", project)
assert len(builds) == len(paths), "Missing/duplicate build source"
assert len(set(builds)) == len(builds), "Duplicate file in build phase"
assert project.count("isa = PBXNativeTarget;") == 2
assert project.count('IPHONEOS_DEPLOYMENT_TARGET = "17.0"') == 6
scheme = ET.parse(root / "CameraLog.xcodeproj/xcshareddata/xcschemes/CameraLog.xcscheme")
for ref in scheme.findall(".//BuildableReference"):
    assert ref.attrib["BlueprintIdentifier"] in definitions
assert scheme.find(".//TestableReference") is not None
print(f"PASS: {len(paths)} Swift files referenced, 2 targets, all object IDs resolved, shared test scheme present.")
print("NOT RUN: Swift compiler, SwiftData runtime, XCTest, iOS UI.")
