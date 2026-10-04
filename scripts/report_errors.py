"""Publish compiler and test failures as GitHub annotations, readable without downloading logs."""
from pathlib import Path
import re
import sys

PATTERN = re.compile(r"(error:|: error|failed|Fatal error|crashed|Assertion|XCTAssert|Test Case .* failed)", re.I)
IGNORED = re.compile(r"(^\s*$|warning:|Testing failed:$|\*\* TEST FAILED \*\*|BUILD FAILED)")


def escape(text):
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


lines = []
for name in sys.argv[1:]:
    path = Path(name)
    if not path.is_file():
        continue
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if PATTERN.search(line) and not IGNORED.search(line) and line not in lines:
            lines.append(line[:600])

print(f"{len(lines)} distinct failure lines")
for index in range(0, min(len(lines), 50), 5):
    chunk = lines[index:index + 5]
    print(f"::error title=Échec {index // 5 + 1}::{escape(chr(10).join(chunk))}")
