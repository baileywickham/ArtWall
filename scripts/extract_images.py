#!/usr/bin/env python3
"""Extract images from the Artpaper app and build a unified catalog for ArtWall."""

import argparse
import json
import os
import shutil
import sys
import urllib.request
from pathlib import Path

ARTPAPER_RESOURCES = Path("/Applications/Artpaper.app/Contents/Resources")
ARTPAPER_IMAGES = Path.home() / "Library/Containers/andriiliakh.Artpaper/Data/Documents/Artpaperimg"
OUTPUT_DIR = Path.home() / "workspace/ArtWall/Data"
IMAGES_DIR = OUTPUT_DIR / "images"

# Packs 0-6 have remote ggpht.com URLs in their metadata
REMOTE_PACKS = {0, 1, 2, 3, 4, 5, 6}
# Packs 7-15 reference local filenames (e.g. "0.jpg")
LOCAL_PACKS = {7, 8, 9, 10, 11, 12, 13, 14, 15}

# Known local 5K image directories
LOCAL_IMAGE_DIRS = {
    2: ARTPAPER_IMAGES / "5k_pack_2" / "2",
    14: ARTPAPER_IMAGES / "5k_pack_14" / "14",
}


def load_packages():
    with open(ARTPAPER_RESOURCES / "packages.json") as f:
        return json.load(f)


def load_pack_metadata(pack_id):
    with open(ARTPAPER_RESOURCES / f"{pack_id}.json") as f:
        return json.load(f)


def copy_local_images(pack_id, items, pack_dir):
    """Copy images from Artpaper's local storage."""
    src_dir = LOCAL_IMAGE_DIRS.get(pack_id)
    if not src_dir or not src_dir.exists():
        print(f"  Pack {pack_id}: no local images found at {src_dir}")
        return 0

    copied = 0
    for idx, item in enumerate(items):
        # Local files are always named by index; ignore the metadata image field
        # which may contain a URL for remote packs that also have local copies
        src = src_dir / f"{idx}.jpg"
        dst = pack_dir / f"{idx:03d}.jpg"
        if dst.exists():
            copied += 1
            continue
        if src.exists():
            shutil.copy2(src, dst)
            copied += 1
        else:
            print(f"  Missing: {src}")
    return copied


def download_remote_image(url, dst):
    """Download an image from a ggpht.com URL at max resolution."""
    # Append =s5000 for highest resolution if not already specified
    if "=s" not in url:
        url = url + "=s5000"
    else:
        url = url.rsplit("=s", 1)[0] + "=s5000"
    # Upgrade to https
    url = url.replace("http://", "https://")

    req = urllib.request.Request(url, headers={"User-Agent": "ArtWall/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        with open(dst, "wb") as f:
            shutil.copyfileobj(resp, f)


def download_remote_images(pack_id, items, pack_dir):
    """Download images from remote URLs."""
    downloaded = 0
    for idx, item in enumerate(items):
        dst = pack_dir / f"{idx:03d}.jpg"
        if dst.exists():
            downloaded += 1
            continue
        url = item.get("image", "")
        if not url or not url.startswith("http"):
            continue
        try:
            download_remote_image(url, dst)
            downloaded += 1
            if downloaded % 10 == 0:
                print(f"  Downloaded {downloaded}/{len(items)}...")
        except Exception as e:
            print(f"  Failed to download {idx}: {e}")
    return downloaded


def build_catalog(packages, selected_packs):
    """Build a unified catalog.json from all pack metadata."""
    catalog = {"packs": [], "images": []}

    for pkg in packages:
        pack_id = pkg["id"]
        items = load_pack_metadata(pack_id)
        pack_dir = IMAGES_DIR / f"pack_{pack_id:02d}"

        catalog["packs"].append({
            "id": pack_id,
            "shortName": pkg["short_name"],
            "name": pkg["name"],
            "imageCount": len(items),
        })

        for idx, item in enumerate(items):
            image_path = f"images/pack_{pack_id:02d}/{idx:03d}.jpg"
            has_file = (pack_dir / f"{idx:03d}.jpg").exists()

            entry = {
                "id": f"{pack_id}_{idx:03d}",
                "packId": pack_id,
                "index": idx,
                "title": item.get("title", "Untitled"),
                "creator": item.get("creator", "Unknown"),
                "year": item.get("year", ""),
                "attribution": item.get("attribution", ""),
                "imagePath": image_path if has_file else None,
            }
            catalog["images"].append(entry)

    return catalog


def main():
    parser = argparse.ArgumentParser(description="Extract Artpaper images for ArtWall")
    parser.add_argument("--packs", type=str, default=None,
                        help="Comma-separated pack IDs to process (e.g. 2,14)")
    parser.add_argument("--skip-download", action="store_true",
                        help="Only copy local images, skip remote downloads")
    args = parser.parse_args()

    packages = load_packages()

    if args.packs:
        selected = set(int(x) for x in args.packs.split(","))
    else:
        selected = set(range(16))

    IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    for pkg in packages:
        pack_id = pkg["id"]
        if pack_id not in selected:
            continue

        items = load_pack_metadata(pack_id)
        pack_dir = IMAGES_DIR / f"pack_{pack_id:02d}"
        pack_dir.mkdir(parents=True, exist_ok=True)

        print(f"Pack {pack_id} ({pkg['short_name']}): {len(items)} images")

        if pack_id in LOCAL_IMAGE_DIRS:
            count = copy_local_images(pack_id, items, pack_dir)
            print(f"  Copied {count}/{len(items)} local images")
        elif pack_id in REMOTE_PACKS and not args.skip_download:
            count = download_remote_images(pack_id, items, pack_dir)
            print(f"  Downloaded {count}/{len(items)} remote images")
        elif pack_id in REMOTE_PACKS:
            print(f"  Skipped (remote, --skip-download)")
        else:
            print(f"  No local images available (pack not downloaded in Artpaper)")

    # Always rebuild catalog from all packs
    print("\nBuilding catalog.json...")
    catalog = build_catalog(packages, selected)
    total_with_images = sum(1 for img in catalog["images"] if img["imagePath"])
    with open(OUTPUT_DIR / "catalog.json", "w") as f:
        json.dump(catalog, f, indent=2)
    print(f"Catalog: {len(catalog['images'])} entries, {total_with_images} with images")


if __name__ == "__main__":
    main()
