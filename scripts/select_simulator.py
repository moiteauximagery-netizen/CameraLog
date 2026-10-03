"""Select an installed, available iPhone simulator without hardcoding an Xcode model."""
import json
import os
import re
import subprocess

data = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
))
candidates = []
for runtime, devices in data["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
    if not match or int(match[1]) < 17:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((int(match[1]), int(match[2])), device))
if not candidates:
    raise SystemExit("No available iPhone simulator with iOS 17 or later on this runner.")
_, device = max(candidates, key=lambda item: (item[0], item[1]["name"]))
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
    environment.write(f'SIMULATOR_UDID={device["udid"]}\n')
print(f'Selected {device["name"]}: {device["udid"]}')
