#!/usr/bin/env python3
"""Create or reuse a persistent, revisioned wallpaper thumbnail."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote, urlsplit


WIDTH = 640
HEIGHT = 384
QUALITY = 82
CACHE_VERSION = f"v2-jpeg-{WIDTH}x{HEIGHT}"


def source_path(value: str) -> Path:
    parsed = urlsplit(value)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return Path(value).expanduser()


def cache_directory() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    if not base:
        base = str(Path.home() / ".cache")
    return Path(base) / "quickshell" / "wallpaper-thumbnails" / CACHE_VERSION


def source_identity(source: Path, stat: os.stat_result) -> dict[str, object]:
    return {
        "source": str(source),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "version": CACHE_VERSION,
    }


def revision(identity: dict[str, object]) -> str:
    payload = json.dumps(identity, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def read_metadata(path: Path) -> dict[str, object] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def write_metadata(path: Path, identity: dict[str, object]) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(identity, sort_keys=True), encoding="utf-8")
    os.replace(temporary, path)


def thumbnail(source: Path) -> str:
    source = source.resolve(strict=True)
    stat = source.stat()
    identity = source_identity(source, stat)

    cache = cache_directory()
    cache.mkdir(parents=True, exist_ok=True)
    path_key = hashlib.sha256(str(source).encode()).hexdigest()[:32]
    output = cache / f"{path_key}.jpg"
    metadata = cache / f"{path_key}.json"

    if not output.is_file() or read_metadata(metadata) != identity:
        temporary = cache / f".{path_key}.{os.getpid()}.tmp.jpg"
        try:
            subprocess.run(
                [
                    "magick",
                    str(source),
                    "-auto-orient",
                    "-thumbnail",
                    f"{WIDTH}x{HEIGHT}^",
                    "-gravity",
                    "center",
                    "-extent",
                    f"{WIDTH}x{HEIGHT}",
                    "-strip",
                    "-quality",
                    str(QUALITY),
                    str(temporary),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            os.replace(temporary, output)
            write_metadata(metadata, identity)
        finally:
            temporary.unlink(missing_ok=True)

    return f"{output.resolve().as_uri()}?v={revision(identity)}"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wallpaper-thumbnail.py IMAGE", file=sys.stderr)
        return 2
    try:
        print(thumbnail(source_path(sys.argv[1])))
    except (OSError, subprocess.SubprocessError) as error:
        print(f"wallpaper thumbnail failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
