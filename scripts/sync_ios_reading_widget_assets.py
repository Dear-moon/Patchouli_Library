#!/usr/bin/env python3
"""Sync the accepted 117 artwork into the WidgetKit-only asset catalog."""

import argparse
import json
from pathlib import Path
import shutil
import struct


ROOT = Path(__file__).resolve().parents[1]
THEMES = (
    "archive", "shelf", "editorial", "constellation",
    "signal", "score", "ink", "festival",
)
CATALOG = ROOT / "ios/ReadingWidgets/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}


def payloads():
    yield CATALOG / "Contents.json", {"info": INFO}
    for theme in THEMES:
        source = ROOT / f"assets/reading_art/{theme}-117.png"
        header = source.read_bytes()[:24]
        if header[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", header[16:24]) != (1536, 1024):
            raise ValueError(f"Expected accepted 1536x1024 PNG: {source}")
        imageset = CATALOG / f"ReadingArtwork_{theme}.imageset"
        yield imageset / "Contents.json", {
            "images": [{"filename": source.name, "idiom": "universal", "scale": "1x"}],
            "info": INFO,
        }
        yield imageset / source.name, source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate without modifying files")
    args = parser.parse_args()
    for target, source in payloads():
        if isinstance(source, dict):
            expected = json.dumps(source, indent=2) + "\n"
            if args.check:
                if target.read_text() != expected:
                    raise ValueError(f"Out-of-date catalog metadata: {target}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(expected)
        elif args.check:
            if source.read_bytes() != target.read_bytes():
                raise ValueError(f"Catalog differs from accepted artwork: {target}")
        else:
            shutil.copyfile(source, target)
    actual = {path.name for path in CATALOG.glob("*.imageset")}
    expected = {f"ReadingArtwork_{theme}.imageset" for theme in THEMES}
    if actual != expected:
        raise ValueError(f"Unexpected imageset inventory: {actual ^ expected}")
    print(f"{'Validated' if args.check else 'Synced'} 8 accepted 117 PNGs and WidgetKit catalog metadata")


if __name__ == "__main__":
    main()
