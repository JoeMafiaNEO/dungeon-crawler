#!/usr/bin/env bash
# Scripted camera pass: renders every level theme under Xvfb, captures
# screenshots, and records a gameplay clip. Outputs land in <out_dir>:
#   <theme>_NN_<label>.png ... clip.mp4 ... camera_pass.log
#
# Usage: capture_footage.sh [project_dir] [out_dir] [--themes village,warlord]
set -euo pipefail

PROJ="${1:-$HOME/workspace/dungeon-crawler}"
OUT="${2:-$PROJ/tools/camera_pass/output}"
EXTRA="${3:-}"
GODOT="${GODOT_BIN:-$HOME/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
DISP=":99"

rm -rf "$OUT"; mkdir -p "$OUT"
pkill -f "Xvfb $DISP" 2>/dev/null || true
Xvfb "$DISP" -screen 0 1280x720x24 &
XVFB_PID=$!
trap 'kill $XVFB_PID 2>/dev/null || true' EXIT
sleep 1

ffmpeg -y -v error -f x11grab -video_size 1280x720 -framerate 15 -i "$DISP" \
	-c:v libx264 -preset veryfast -pix_fmt yuv420p "$OUT/clip.mp4" &
FF_PID=$!
sleep 1

# shellcheck disable=SC2086
DISPLAY="$DISP" timeout 900 "$GODOT" --path "$PROJ" \
	res://tools/camera_pass/camera_pass.tscn \
	--resolution 1280x720 -- --shot-dir "$OUT" $EXTRA \
	2>&1 | tee "$OUT/camera_pass.log" | grep -E "CameraPass|ERROR|SCRIPT" || true

kill "$FF_PID" 2>/dev/null || true
wait "$FF_PID" 2>/dev/null || true
echo "--- output ---"
ls -la "$OUT"
