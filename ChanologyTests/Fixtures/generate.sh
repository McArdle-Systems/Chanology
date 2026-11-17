#!/bin/sh
# Regenerates the tiny media fixtures used by MediaFixtureTests and the debug
# Xcode previews (PreviewMedia). Needs ffmpeg with libvpx and libx264.
#
# Video must be 4:2:0 (yuv420p): ffmpeg's test pattern is RGB, and left alone
# libvpx-vp9 encodes it as VP9 profile 1 / 4:4:4, which WebKit can't play.
set -e
cd "$(dirname "$0")"
SRC="testsrc=size=64x48:rate=10:duration=1"

ffmpeg -v error -y -f lavfi -i "$SRC" -frames:v 1 -q:v 5 sample.jpg
ffmpeg -v error -y -f lavfi -i "$SRC" \
    -vf "split[a][b];[a]palettegen=max_colors=32[p];[b][p]paletteuse" -loop 0 sample.gif
ffmpeg -v error -y -f lavfi -i "$SRC" \
    -c:v libvpx-vp9 -profile:v 0 -pix_fmt yuv420p -b:v 50k -an sample.webm
ffmpeg -v error -y -f lavfi -i "$SRC" \
    -c:v libx264 -pix_fmt yuv420p -crf 35 -movflags +faststart -an sample.mp4
