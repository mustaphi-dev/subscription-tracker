#!/bin/bash
# encode.sh FRAMES_DIR NAME [stage.py options]
# Put transparent Cycles frames on the Wince stage (stage.py), then write
# assets/onboarding/NAME.mp4 (H.264, plays everywhere) and NAME.jpg (frame 1).
# PY picks the Python that has numpy, scipy and pillow (default python3).
set -e
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
SRC=$1; NAME=$2; shift 2
TMP=$(mktemp -d)
"${PY:-python3}" "$HERE/stage.py" "$SRC" "$TMP" "$@" > /dev/null
ffmpeg -y -loglevel error -framerate 24 -i "$TMP/f%04d.png" -c:v libx264 -profile:v high -preset slow -crf 20 \
  -pix_fmt yuv420p -movflags +faststart -an "$REPO/assets/onboarding/$NAME.mp4"
ffmpeg -y -loglevel error -i "$TMP/f0001.png" -q:v 3 "$REPO/assets/onboarding/$NAME.jpg"
rm -rf "$TMP"
