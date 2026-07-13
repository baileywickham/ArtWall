#!/usr/bin/env python3
"""Fetch high-resolution public-domain paintings from the Art Institute of
Chicago Open Access API into an ArtWall pack.

Only artworks whose master image is at least MIN_W x MIN_H are downloaded, so
nothing in the pack needs upscaling on a 3024x1964 display. Boosted (curated
highlight) works are fetched first.

Re-runnable: already-downloaded images are skipped and catalog.json is merged,
not rewritten. Note: scripts/extract_images.py rewrites catalog.json from
Artpaper metadata — re-run this script afterwards to restore this pack's
entries (images on disk are untouched).

Usage: python3 scripts/fetch_museum_pack.py [--limit 80]
"""

import argparse
import json
import struct
import time
import urllib.parse
import urllib.request
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "Data"
PACK_ID = 100
PACK_SHORT = "AIC"
PACK_NAME = "Art Institute of Chicago (Open Access)"
ATTRIBUTION = "The Art Institute of Chicago, CC0"
SCREEN_W, SCREEN_H = 3024, 1964
IIIF_MAX = 3000       # AIC serves at most 3000px on the long side
MAX_SCALE = 1.03      # accept up to 3% upscale (imperceptible)


def fill_scale(w, h):
    """Upscale factor macOS needs to fill the screen with a w x h image."""
    return max(SCREEN_W / w, SCREEN_H / h) if w and h else 99.0


def predicted_served(w, h):
    """Dimensions AIC's IIIF will actually serve for a w x h master."""
    if max(w, h) <= IIIF_MAX:
        return w, h
    f = IIIF_MAX / max(w, h)
    return round(w * f), round(h * f)
API = "https://api.artic.edu/api/v1/artworks/search"
IIIF = "https://www.artic.edu/iiif/2/{image_id}/full/full/0/default.jpg"
UA = "ArtWall/1.0 (github.com/baileywickham/ArtWall; bailey@usebits.com)"


def api_search(page):
    params = {
        "query": json.dumps({
            "bool": {
                "must": [
                    {"term": {"is_public_domain": True}},
                    {"match": {"artwork_type_title": "Painting"}},
                ],
                "should": [{"term": {"is_boosted": True}}],
            }
        }),
        "fields": "id,title,artist_display,date_display,image_id,thumbnail",
        "limit": 100,
        "page": page,
    }
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def jpeg_dimensions(path):
    """Read width/height from JPEG SOF marker without external deps."""
    with open(path, "rb") as f:
        data = f.read()
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return 0, 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=80)
    args = parser.parse_args()

    pack_dir = DATA_DIR / "images" / f"pack_{PACK_ID}"
    pack_dir.mkdir(parents=True, exist_ok=True)

    candidates, page = [], 1
    while len(candidates) < args.limit * 3 and page <= 10:
        result = api_search(page)
        for art in result.get("data", []):
            thumb = art.get("thumbnail") or {}
            w, h = thumb.get("width") or 0, thumb.get("height") or 0
            if art.get("image_id") and fill_scale(*predicted_served(w, h)) <= MAX_SCALE:
                candidates.append(art)
        if page >= result.get("pagination", {}).get("total_pages", 1):
            break
        page += 1
    print(f"{len(candidates)} candidates within {MAX_SCALE}x of {SCREEN_W}x{SCREEN_H}")

    entries, fetched = [], 0
    for idx, art in enumerate(candidates):
        if fetched >= args.limit:
            break
        dst = pack_dir / f"{idx:03d}.jpg"
        if not dst.exists():
            url = IIIF.format(image_id=art["image_id"])
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=120) as resp:
                    dst.write_bytes(resp.read())
                time.sleep(0.7)
            except Exception as e:
                print(f"  skip {art['title'][:40]}: {e}")
                continue
            w, h = jpeg_dimensions(dst)
            if fill_scale(w, h) > MAX_SCALE:
                print(f"  drop {art['title'][:40]}: served {w}x{h}")
                dst.unlink()
                continue
        fetched += 1
        entries.append({
            "id": f"{PACK_ID}_{idx:03d}",
            "packId": PACK_ID,
            "index": idx,
            "title": art.get("title") or "Untitled",
            "creator": (art.get("artist_display") or "").split("\n")[0],
            "year": art.get("date_display") or "",
            "attribution": ATTRIBUTION,
            "imagePath": f"images/pack_{PACK_ID}/{idx:03d}.jpg",
        })
        print(f"  [{fetched}/{args.limit}] {art['title'][:60]}")

    catalog_path = DATA_DIR / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    catalog["packs"] = [p for p in catalog["packs"] if p["id"] != PACK_ID]
    catalog["images"] = [i for i in catalog["images"] if i["packId"] != PACK_ID]
    catalog["packs"].append({
        "id": PACK_ID, "shortName": PACK_SHORT,
        "name": PACK_NAME, "imageCount": len(entries),
    })
    catalog["images"].extend(entries)
    catalog_path.write_text(json.dumps(catalog, indent=1, ensure_ascii=False))
    print(f"wrote {len(entries)} images to catalog as pack {PACK_ID}")


if __name__ == "__main__":
    main()
