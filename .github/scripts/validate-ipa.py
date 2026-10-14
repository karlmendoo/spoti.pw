"""Validate the clean baseline's IPA before patching and artifact upload."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import sys
import tempfile
import zipfile


def validate(path, kit_path=None):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError("IPA is missing or empty")
    if not zipfile.is_zipfile(path):
        raise ValueError("Download is not a ZIP/IPA archive; it may be an HTML error page")

    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError("IPA contains duplicate archive entries")
        for name in names:
            member = PurePosixPath(name)
            if member.is_absolute() or ".." in member.parts or "\\" in name:
                raise ValueError("IPA contains an invalid archive path")
        damaged = archive.testzip()
        if damaged:
            raise ValueError("IPA contains a damaged ZIP entry: " + damaged)

        apps = {
            PurePosixPath(name).parts[1]
            for name in names
            if len(PurePosixPath(name).parts) >= 3
            and PurePosixPath(name).parts[0] == "Payload"
            and PurePosixPath(name).parts[1].endswith(".app")
        }
        if len(apps) != 1:
            raise ValueError("IPA must contain exactly one Payload/*.app bundle")
        app_name = apps.pop()
        if kit_path:
            with zipfile.ZipFile(kit_path) as kit:
                manifest = json.loads(kit.read("kit.json"))
            checked = 0
            for name, expected in manifest["integrity"].items():
                if not name.startswith("files/"):
                    continue
                relative = name.removeprefix("files/")
                if relative in manifest["templates"]:
                    continue  # Upstream fills these with Spotify's bundle/version values.
                actual = hashlib.sha256(archive.read(f"Payload/{app_name}/{relative}")).hexdigest()
                if actual != expected:
                    raise ValueError("Patched IPA changed an official kit file: " + relative)
                checked += 1
            print(f"Official release payload hashes preserved: {checked} files")
        with tempfile.TemporaryDirectory(prefix="spoti-ipa-validation-") as temporary:
            archive.extractall(temporary)
            app = Path(temporary) / "Payload" / app_name
            with (app / "Info.plist").open("rb") as source:
                info = plistlib.load(source)
            if info.get("CFBundleIdentifier") != "com.spotify.client":
                raise ValueError("Payload app is not Spotify")
            version = info.get("CFBundleShortVersionString")
            if version != "9.1.90":
                raise ValueError("Expected Spotify 9.1.90, found " + str(version))
            if info.get("CFBundleExecutable") != "Spotify":
                raise ValueError("Spotify app has an unexpected executable")
            executable = app / "Spotify"
            if not executable.is_file() or executable.stat().st_size == 0:
                raise ValueError("Spotify app executable is missing or empty")

    print(f"IPA exists: {path.stat().st_size} bytes")
    print("ZIP integrity and complete extraction: passed")
    print(f"Payload/{app_name}: valid Spotify app bundle")
    print("CFBundleShortVersionString: 9.1.90")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--kit", type=Path, help="Verify the output contains the unchanged official binaries")
    args = parser.parse_args()
    try:
        validate(args.ipa, args.kit)
    except (OSError, ValueError, KeyError, RuntimeError, NotImplementedError, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        print("::error::IPA validation failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
