#!/usr/bin/env python3
"""Fetch CC0 textures from Poly Haven into assets/.

Resolves each query via the public Poly Haven API (no key needed), takes the
top result, and downloads the 1K diffuse map. The game runs fine without these
(procedural fallback); this just makes it prettier.

Usage:
    python3 tools/fetch_assets.py

Manual alternative: download any 1K JPG/PNG albedo from polyhaven.com or
ambientcg.com and save as assets/tex_wall.jpg, tex_floor.jpg, tex_ceiling.jpg.
"""
import json
import sys
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

QUERIES = [
    ("tex_wall", "yellow plaster wall"),
    ("tex_floor", "dirty carpet"),
    ("tex_ceiling", "acoustic ceiling tile"),
]

API_SEARCH = "https://api.polyhaven.com/search?q={q}&t=textures"
API_FILES = "https://api.polyhaven.com/files/{slug}"
TIMEOUT = 30


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "backrooms-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def pick_diffuse(files: Dict) -> Optional[str]:
    """Prefer Diffuse 1k JPG, else smallest diffuse available."""
    diffuse = files.get("Diffuse") or files.get("diffuse")
    if not diffuse:
        return None
    for res in ("1k", "2k", "4k", "8k"):
        entry = diffuse.get(res)
        if entry:
            if "jpg" in entry:
                return entry["jpg"]["url"]
            if "png" in entry:
                return entry["png"]["url"]
    return None


def fetch_one(name: str, query: str) -> Optional[str]:
    print(f"[{name}] searching '{query}' ...")
    slug = get_json(API_SEARCH.format(q=query.replace(" ", "%20")))["results"][0]["slug"]
    print(f"[{name}] top hit: {slug}")
    url = pick_diffuse(get_json(API_FILES.format(slug=slug)))
    if not url:
        raise RuntimeError(f"no diffuse map found for {slug}")
    ext = ".png" if url.endswith(".png") else ".jpg"
    dest = ASSETS / f"{name}{ext}"
    print(f"[{name}] downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "backrooms-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as fh:
        fh.write(resp.read())
    print(f"[{name}] saved {dest} ({dest.stat().st_size // 1024} KB)")
    return f"{name}{ext} <- https://polyhaven.com/a/{slug} (CC0) via {url}"


def main() -> int:
    ASSETS.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []
    failed = 0
    for name, query in QUERIES:
        try:
            lines.append(fetch_one(name, query))
        except Exception as exc:  # noqa: BLE001 - report and continue
            failed += 1
            print(f"[{name}] FAILED: {exc}", file=sys.stderr)
    if lines:
        (ASSETS / "SOURCES.txt").write_text(
            "CC0 textures fetched from Poly Haven (https://polyhaven.com, CC0 1.0).\n"
            + "\n".join(lines)
            + "\n"
        )
    print()
    print("Optional sounds (manual, needs a free freesound.org account):")
    print("  fluorescent hum loop  -> assets/hum_loop.ogg")
    print("  dark room drone loop  -> assets/drone_loop.ogg")
    print("  monster screech       -> assets/screech.ogg")
    print("  wooden door knock     -> assets/thunk.ogg")
    print("  metal door creak      -> assets/creak.ogg")
    print("Check each sound's license (CC0 or CC-BY with credit).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
