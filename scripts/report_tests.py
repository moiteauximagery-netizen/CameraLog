"""Publish the executed test list as a GitHub notice, readable without downloading artifacts."""
import json
import subprocess
import sys

bundle = sys.argv[1]


def tool(kind):
    output = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle])
    return json.loads(output)


summary = tool("summary")
cases = []


def walk(node):
    if node.get("nodeType") == "Test Case":
        cases.append(f'{node.get("result", "?")}: {node.get("name")}')
    for child in node.get("children", []):
        walk(child)


for node in tool("tests").get("testNodes", []):
    walk(node)
counts = {key: summary.get(key) for key in ("result", "totalTestCount", "passedTests", "failedTests", "skippedTests")}
devices = [f'{d.get("device", {}).get("deviceName")} {d.get("device", {}).get("osVersion")}'
           for d in summary.get("devicesAndConfigurations", [])]
text = f"{counts} on {devices}\n" + "\n".join(cases)
print(text)
print("::notice title=Tests exécutés::" + text.replace("%", "%25").replace("\n", "%0A"))
