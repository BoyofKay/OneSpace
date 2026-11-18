#!/usr/bin/env python3
"""Fail the iOS build if the archived bundle doesn't match the selected backend."""
import argparse
import plistlib
import sys
import zipfile
from pathlib import Path

EXPECTED = {
    "qa": ("com.onespace.onespace.qa", "onespace-preview", "OneSpace QA"),
    "production": ("com.onespace.onespace", "onespace", "OneSpace"),
}


def verify(info: dict, environment: str) -> None:
    bundle, scheme, display = EXPECTED[environment]
    schemes = [
        s for url_type in info.get("CFBundleURLTypes", [])
        for s in url_type.get("CFBundleURLSchemes", [])
    ]
    checks = {
        "CFBundleIdentifier": (info.get("CFBundleIdentifier"), bundle),
        "OneSpaceEnvironment": (info.get("OneSpaceEnvironment"), environment),
        "CFBundleDisplayName": (info.get("CFBundleDisplayName"), display),
        "auth scheme": (schemes, scheme),
    }
    for label, (value, expected) in checks.items():
        okay = expected in value if isinstance(value, list) else value == expected
        if not okay:
            sys.exit(f"iOS release rejected: {label}={value!r}, expected {expected!r}")
    print(f"Verified iOS {environment} identity and callback: {bundle}")


def main() -> None:
    parser = argparse.ArgumentParser()
    arg = parser.add_mutually_exclusive_group(required=True)
    arg.add_argument("--app", type=Path)
    arg.add_argument("--ipa", type=Path)
    parser.add_argument("--environment", choices=sorted(EXPECTED), required=True)
    args = parser.parse_args()
    if args.app:
        with (args.app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    else:
        with zipfile.ZipFile(args.ipa) as archive:
            names = [name for name in archive.namelist()
                     if name.startswith("Payload/") and name.endswith(".app/Info.plist")]
            if len(names) != 1:
                sys.exit("Expected exactly one app Info.plist in the IPA")
            info = plistlib.loads(archive.read(names[0]))
    verify(info, args.environment)


if __name__ == "__main__":
    main()
