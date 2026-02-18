#!/bin/bash
set -euo pipefail

# Generate ArtWall app icon using ImageMagick
# Creates a picture-frame style icon with a gradient landscape

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ICONSET_DIR="${PROJECT_DIR}/.build-icon/ArtWall.iconset"
ICNS_PATH="${PROJECT_DIR}/Sources/ArtWall/Resources/ArtWall.icns"

rm -rf "${PROJECT_DIR}/.build-icon"
mkdir -p "${ICONSET_DIR}"
mkdir -p "$(dirname "${ICNS_PATH}")"

SIZE=1024

convert -size ${SIZE}x${SIZE} xc:none \
  \( -size ${SIZE}x${SIZE} xc:none \
    -fill '#2C1810' -draw "roundrectangle 40,40 984,984 80,80" \
    -fill '#3D2317' -draw "roundrectangle 70,70 954,954 60,60" \
    -fill '#5C3A28' -draw "roundrectangle 90,90 934,934 50,50" \
    -fill '#3D2317' -draw "roundrectangle 120,120 904,904 40,40" \
  \) -composite \
  \( -size 744x744 gradient:'#1a0533'-'#0d1b2a' -geometry +140+140 \) -composite \
  \( -size 744x372 gradient:'#0d1b2a'-'#1b2838' -geometry +140+512 \) -composite \
  \( -size 744x744 xc:none \
    -fill '#ff6b35' -draw "circle 620,260 620,210" \
    -fill '#ff8c42' -draw "circle 620,265 620,225" \
    -geometry +140+140 \) -composite \
  \( -size 744x744 xc:none \
    -fill '#1a3a2a' -draw "polygon 0,744 200,300 400,744" \
    -fill '#234d35' -draw "polygon 150,744 350,400 550,744" \
    -fill '#1a3a2a' -draw "polygon 400,744 600,350 744,744" \
    -geometry +140+140 \) -composite \
  \( -size 744x744 xc:none \
    -fill '#ffd700' -draw "point 200,200" -fill '#ffd700' -draw "circle 200,200 200,198" \
    -fill '#ffd700' -draw "circle 400,150 400,148" \
    -fill '#ffd700' -draw "circle 600,180 600,178" \
    -fill '#ffd700' -draw "circle 300,120 300,118" \
    -fill '#ffd700' -draw "circle 500,100 500,098" \
    -fill '#ffd700' -draw "circle 150,160 150,158" \
    -geometry +140+140 \) -composite \
  "${ICONSET_DIR}/icon_1024.png"

# Generate all required sizes
for size in 16 32 64 128 256 512; do
  convert "${ICONSET_DIR}/icon_1024.png" -resize ${size}x${size} "${ICONSET_DIR}/icon_${size}x${size}.png"
done
for size in 16 32 128 256 512; do
  double=$((size * 2))
  cp "${ICONSET_DIR}/icon_${double}.png" "${ICONSET_DIR}/icon_${size}x${size}@2x.png" 2>/dev/null || \
  convert "${ICONSET_DIR}/icon_1024.png" -resize ${double}x${double} "${ICONSET_DIR}/icon_${size}x${size}@2x.png"
done

# Rename to match iconutil expectations
cd "${ICONSET_DIR}"
mv icon_16x16.png icon_16x16.png 2>/dev/null || true
mv icon_64.png icon_32x32@2x.png 2>/dev/null || true

iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"

echo "==> Icon created at ${ICNS_PATH}"
rm -rf "${PROJECT_DIR}/.build-icon"
