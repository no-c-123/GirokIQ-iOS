#!/usr/bin/env python3
"""Print the UDID of a usable iPad simulator.

The app is iPad-only (TARGETED_DEVICE_FAMILY = 2), so an iPhone simulator
cannot install the test host. Runner images change their device lists between
Xcode releases, so the device is discovered rather than hard-coded by name.
"""

import json
import subprocess
import sys


def main():
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True,
    ).stdout

    best = None
    for runtime, devices in json.loads(raw)["devices"].items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable") or "iPad" not in device["name"]:
                continue
            # Runtime identifiers sort lexicographically by version, so the
            # last one is the newest iOS available on this runner.
            if best is None or runtime > best[0]:
                best = (runtime, device["udid"], device["name"])

    if best is None:
        sys.exit("No available iPad simulator on this machine.")

    print(best[1])
    print(f"Selected {best[2]} on {best[0].rsplit('.', 1)[-1]}", file=sys.stderr)


if __name__ == "__main__":
    main()
