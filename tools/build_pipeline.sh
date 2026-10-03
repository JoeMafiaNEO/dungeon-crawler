#!/usr/bin/env bash
# Full build pipeline for the dungeon crawler.
#   1. Headless validation (tests/playtest.gd) — aborts on failure.
#   2. Scripted camera pass (tools/capture_footage.sh) — screenshots + clip.
#   3. Project zip, ready to upload.
#
# Outputs:
#   ~/workspace/dungeon-crawler-<stamp>.zip
#   tools/camera_pass/output/  (shots + clip.mp4 + camera_pass.log)
set -euo pipefail

PROJ="$HOME/workspace/dungeon-crawler"
GODOT="${GODOT_BIN:-$HOME/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
STAMP="$(date +%Y%m%d-%H%M)"
OUT="$PROJ/tools/camera_pass/output"

echo "=== 1/3 validation ==="
TEST_OUT="$(mktemp)"
"$GODOT" --headless --path "$PROJ" -s tests/playtest.gd >"$TEST_OUT" 2>&1 || true
grep -E "Results:|FAIL" "$TEST_OUT" | tail -8
if ! grep -q "0 failed" "$TEST_OUT"; then
	echo "VALIDATION FAILED — aborting pipeline"
	rm -f "$TEST_OUT"
	exit 1
fi
rm -f "$TEST_OUT"

echo "=== 2/3 footage ==="
"$PROJ/tools/capture_footage.sh" "$PROJ" "$OUT"

echo "=== 3/3 zip ==="
cd "$PROJ"
ZIP="$HOME/workspace/dungeon-crawler-$STAMP.zip"
rm -f "$ZIP"
zip -qr "$ZIP" . -x ".godot/*" "tools/camera_pass/output/*"
ls -la "$ZIP"
echo "=== done ==="
echo "zip: $ZIP"
echo "footage: $OUT"
ls "$OUT"
