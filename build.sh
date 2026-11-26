#!/bin/bash
# Builds the 11Cam release packages into ./out (run in Terminal on the Mac: arm64e needs Xcode's compiler).
set -e
cd "$(dirname "$0")"
export THEOS="${THEOS:-$HOME/theos}"
rm -rf out; mkdir -p out
make clean package
cp "$(ls -t packages/*.deb | head -1)" out/
make clean package EXP="STEREO LIGHTINGPREVIEW NIGHTMODE LIVETEXTDETECT" DIAG=DIAG_LOG
f=$(ls -t packages/*.deb | head -1); cp "$f" "out/$(basename "$f" .deb)-experiments-diag.deb"
ls -la out
