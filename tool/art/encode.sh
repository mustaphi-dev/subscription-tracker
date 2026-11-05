#!/bin/bash
# encode.sh FRAMES_DIR NAME BG GLOW
# Composite transparent Cycles frames over the page gradient, then write
# assets/onboarding/NAME.mp4 (H.264, plays everywhere) and NAME.jpg (frame 1).
set -e
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
SRC=$1; NAME=$2; BG=$3; GLOW=$4
TMP=$(mktemp -d)
python3 "$HERE/post.py" "$SRC" "$TMP" --bg "$BG" --glow "$GLOW" --bloom 0.38 > /dev/null
ffmpeg -y -loglevel error -framerate 24 -i "$TMP/f%04d.png" -c:v libx264 -profile:v high -preset slow -crf 21 \
  -pix_fmt yuv420p -movflags +faststart -an "$REPO/assets/onboarding/$NAME.mp4"
ffmpeg -y -loglevel error -i "$TMP/f0001.png" -q:v 3 "$REPO/assets/onboarding/$NAME.jpg"
rm -rf "$TMP"
