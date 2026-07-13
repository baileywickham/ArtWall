#!/usr/bin/env python3
"""Fetch high-resolution public-domain paintings from museum open-access APIs
into ArtWall packs.

Sources (all CC0/public domain, paintings only, curated highlights first):
  aic  pack 100  Art Institute of Chicago  (IIIF, capped 3000px long side)
  met  pack 101  The Metropolitan Museum of Art  (full originals)
  cma  pack 102  Cleveland Museum of Art  (print rendition, ~3400px)

Only images needing <= 3% upscaling on a 3024x1964 display are kept.
Oversized Met originals are downscaled to 4500px to keep the pack lean.

Re-runnable: existing files are kept, catalog.json is merged non-destructively.
Note: scripts/extract_images.py rewrites catalog.json — re-run this script
afterwards to restore these packs' entries (images on disk are untouched).

Usage:
  python3 scripts/fetch_museum_pack.py --source aic --limit 400
  python3 scripts/fetch_museum_pack.py --source all --total 1000
"""

import argparse
import json
import struct
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "Data"
SCREEN_W, SCREEN_H = 3024, 1964
MAX_SCALE = 1.03      # accept up to 3% upscale (imperceptible)
MAX_LONG_SIDE = 4500  # downscale anything bigger to keep disk usage sane
UA = "ArtWall/1.0 (github.com/baileywickham/ArtWall; bailey@usebits.com)"

PACKS = {
    "aic": (100, "AIC", "Art Institute of Chicago (Open Access)",
            "The Art Institute of Chicago, CC0"),
    "met": (101, "Met", "The Metropolitan Museum of Art (Open Access)",
            "The Metropolitan Museum of Art, CC0"),
    "cma": (102, "Cleveland", "Cleveland Museum of Art (Open Access)",
            "Cleveland Museum of Art, CC0"),
}


def fill_scale(w, h):
    """Upscale factor macOS needs to fill the screen with a w x h image."""
    return max(SCREEN_W / w, SCREEN_H / h) if w and h else 99.0


def get_json(url, attempts=5):
    """GET JSON with exponential backoff on rate limits and server errors."""
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 500, 502, 503) and attempt < attempts - 1:
                wait = 30 * (attempt + 1)
                print(f"  HTTP {e.code}, backing off {wait}s...")
                time.sleep(wait)
                continue
            raise


def download(url, dst):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as resp:
        dst.write_bytes(resp.read())


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


def shrink_if_huge(path):
    w, h = jpeg_dimensions(path)
    if max(w, h) > MAX_LONG_SIDE:
        subprocess.run(["sips", "-Z", str(MAX_LONG_SIDE), str(path)],
                       capture_output=True, check=False)


class PackWriter:
    """Accumulates validated images for one pack, skipping existing files."""

    def __init__(self, source, limit):
        self.pack_id, self.short, self.name, self.attribution = PACKS[source]
        self.limit = limit
        self.dir = DATA_DIR / "images" / f"pack_{self.pack_id}"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.entries = []

    @property
    def done(self):
        return len(self.entries) >= self.limit

    def add(self, url, title, creator, year, downscale=False):
        idx = len(self.entries)
        dst = self.dir / f"{idx:03d}.jpg"
        if not dst.exists():
            try:
                download(url, dst)
            except Exception as e:
                print(f"  skip {title[:50]}: {e}")
                return False
            time.sleep(0.8)
            w, h = jpeg_dimensions(dst)
            if fill_scale(w, h) > MAX_SCALE:
                dst.unlink()
                return False
            if downscale:
                shrink_if_huge(dst)
        self.entries.append({
            "id": f"{self.pack_id}_{idx:03d}",
            "packId": self.pack_id,
            "index": idx,
            "title": title or "Untitled",
            "creator": creator or "",
            "year": year or "",
            "attribution": self.attribution,
            "imagePath": f"images/pack_{self.pack_id}/{idx:03d}.jpg",
        })
        print(f"  [{self.short} {len(self.entries)}/{self.limit}] {title[:60]}")
        return True


def fetch_aic(limit):
    pack = PackWriter("aic", limit)
    iiif_max = 3000  # AIC serves at most 3000px on the long side
    page = 1
    while not pack.done and page <= 30:
        params = {
            "query": json.dumps({"bool": {
                "must": [{"term": {"is_public_domain": True}},
                         {"match": {"artwork_type_title": "Painting"}}],
                "should": [{"term": {"is_boosted": True}}],
            }}),
            "fields": "id,title,artist_display,date_display,image_id,thumbnail",
            "limit": 100, "page": page,
        }
        result = get_json("https://api.artic.edu/api/v1/artworks/search?"
                          + urllib.parse.urlencode(params))
        for art in result.get("data", []):
            if pack.done:
                break
            thumb = art.get("thumbnail") or {}
            w, h = thumb.get("width") or 0, thumb.get("height") or 0
            if w and h and max(w, h) > iiif_max:
                f = iiif_max / max(w, h)
                w, h = round(w * f), round(h * f)
            if not art.get("image_id") or fill_scale(w, h) > MAX_SCALE:
                continue
            url = (f"https://www.artic.edu/iiif/2/{art['image_id']}"
                   "/full/full/0/default.jpg")
            pack.add(url, art.get("title"),
                     (art.get("artist_display") or "").split("\n")[0],
                     art.get("date_display"))
        if page >= result.get("pagination", {}).get("total_pages", 1):
            break
        page += 1
    return pack


def fetch_met(limit):
    pack = PackWriter("met", limit)
    base = "https://collectionapi.metmuseum.org/public/collection/v1"
    searches = [  # curated highlights first, then broader painting sweeps
        "hasImages=true&isHighlight=true&medium=Paintings&q=painting",
        "hasImages=true&medium=Paintings&departmentIds=11&q=landscape",
        "hasImages=true&medium=Paintings&departmentIds=11&q=painting",
        "hasImages=true&medium=Paintings&departmentIds=1&q=painting",
        "hasImages=true&medium=Paintings&departmentIds=6&q=landscape",
    ]
    seen = set()
    for qs in searches:
        if pack.done:
            break
        ids = get_json(f"{base}/search?{qs}").get("objectIDs") or []
        for oid in ids:
            if pack.done:
                break
            if oid in seen:
                continue
            seen.add(oid)
            try:
                obj = get_json(f"{base}/objects/{oid}")
            except Exception:
                continue
            time.sleep(0.25)
            if (not obj.get("isPublicDomain")
                    or obj.get("classification") != "Paintings"
                    or not obj.get("primaryImage")):
                continue
            pack.add(obj["primaryImage"], obj.get("title"),
                     obj.get("artistDisplayName"), obj.get("objectDate"),
                     downscale=True)
    return pack


def fetch_cma(limit):
    pack = PackWriter("cma", limit)
    base = "https://openaccess-api.clevelandart.org/api/artworks/"
    skip = 0
    while not pack.done:
        result = get_json(f"{base}?cc0=1&has_image=1&type=Painting"
                          f"&limit=100&skip={skip}")
        data = result.get("data", [])
        if not data:
            break
        for art in data:
            if pack.done:
                break
            rend = (art.get("images") or {}).get("print") or {}
            w = int(rend.get("width") or 0)
            h = int(rend.get("height") or 0)
            if not rend.get("url") or fill_scale(w, h) > MAX_SCALE:
                continue
            creators = art.get("creators") or []
            creator = creators[0].get("description", "") if creators else ""
            pack.add(rend["url"], art.get("title"), creator.split("(")[0].strip(),
                     art.get("creation_date"))
        skip += 100
    return pack


def merge_catalog(packs):
    catalog_path = DATA_DIR / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    for pack in packs:
        catalog["packs"] = [p for p in catalog["packs"] if p["id"] != pack.pack_id]
        catalog["images"] = [i for i in catalog["images"]
                             if i["packId"] != pack.pack_id]
        catalog["packs"].append({
            "id": pack.pack_id, "shortName": pack.short,
            "name": pack.name, "imageCount": len(pack.entries),
        })
        catalog["images"].extend(pack.entries)
        print(f"catalog: pack {pack.pack_id} ({pack.short}) -> "
              f"{len(pack.entries)} images")
    catalog_path.write_text(json.dumps(catalog, indent=1, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", choices=[*PACKS, "all"], default="aic")
    parser.add_argument("--limit", type=int, default=80)
    parser.add_argument("--total", type=int, default=1000,
                        help="target across all sources (with --source all)")
    args = parser.parse_args()

    fetchers = {"aic": fetch_aic, "met": fetch_met, "cma": fetch_cma}
    if args.source == "all":
        quotas = {"aic": args.total * 2 // 5, "met": args.total * 3 // 10,
                  "cma": args.total * 3 // 10}
    else:
        quotas = {args.source: args.limit}
    packs = []
    for source, quota in quotas.items():
        try:
            packs.append(fetchers[source](quota))
        except Exception as e:
            print(f"{source} aborted after an unrecoverable error: {e}")
    # Merge whatever succeeded; a partial pack is still usable.
    merge_catalog(packs)


if __name__ == "__main__":
    main()
