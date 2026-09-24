#!/usr/bin/env python3
"""Install localized permission descriptions in the native macOS app bundle."""
import json
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
source = Path(__file__).resolve().parent.parent / "Sources/WiFiPriorityCore/Resources"
languages = []
for file in sorted(source.glob("*.json")):
    language = file.stem
    translations = json.loads(file.read_text(encoding="utf-8"))
    languages.append(language)
    target = app / "Contents/Resources" / f"{language}.lproj"
    target.mkdir(parents=True, exist_ok=True)
    values = {key: translations["locationUsage"] for key in (
        "NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"
    )}
    (target / "InfoPlist.strings").write_bytes(plistlib.dumps(values))
info = app / "Contents/Info.plist"
values = plistlib.loads(info.read_bytes())
values["CFBundleDevelopmentRegion"] = "en"
values["CFBundleLocalizations"] = languages
info.write_bytes(plistlib.dumps(values))
