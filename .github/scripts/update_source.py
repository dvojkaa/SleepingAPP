#!/usr/bin/env python3
"""Aktualizuje altstore-source.json o nově vydanou verzi appky.

Spouští ho GitHub Actions workflow (.github/workflows/release.yml) po sestavení
a nahrání .ipa do GitHub Release. Skript je idempotentní - pokud daná verze
v source JSONu už existuje, nahradí ji (nevytvoří duplicitní záznam).
"""
import argparse
import datetime
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_PATH = ROOT / "altstore-source.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Verze appky, např. 1.0.0")
    parser.add_argument("--size", required=True, type=int, help="Velikost .ipa v bajtech")
    parser.add_argument("--repo", required=True, help="owner/repo, např. dvojkaa/SleepingAPP")
    args = parser.parse_args()

    if not SOURCE_PATH.exists():
        print(f"Chybí {SOURCE_PATH}", file=sys.stderr)
        sys.exit(1)

    data = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    app = data["apps"][0]

    download_url = (
        f"https://github.com/{args.repo}/releases/download/"
        f"v{args.version}/SleepTracker.ipa"
    )
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    new_version = {
        "version": args.version,
        "date": now,
        "localizedDescription": f"Verze {args.version}.",
        "downloadURL": download_url,
        "size": args.size,
        "minOSVersion": "17.0",
    }

    versions = [v for v in app.get("versions", []) if v.get("version") != args.version]
    versions.insert(0, new_version)
    app["versions"] = versions

    # Pohodlné "top-level" duplikáty pro klienty, co čtou jen nejnovější verzi
    # přímo z appky (ne z pole versions).
    app["version"] = args.version
    app["versionDate"] = now
    app["size"] = args.size
    app["downloadURL"] = download_url

    SOURCE_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"altstore-source.json aktualizován na verzi {args.version}")


if __name__ == "__main__":
    main()
