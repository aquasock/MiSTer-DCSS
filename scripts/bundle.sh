#!/bin/bash
# Assembles work/bundle: the tree that is copied to /media/fat on the MiSTer.
# Run build-deps.sh and build-crawl.sh first.
set -euo pipefail
. "$(dirname "$0")/env.sh"

OUT="$WORK/bundle"
GAME="$OUT/dcss"
rm -rf "$OUT"
mkdir -p "$GAME" "$OUT/Scripts"
cp -a "$WORK/stage/dcss/." "$GAME/"
# License texts travel with the game: DCSS's own, and this project's.
cp "$SRC/crawl/LICENSE" "$GAME/docs/LICENSE-DCSS"
cp "$ROOT/LICENSE.txt" "$ROOT/COPYING.ZLIB" "$ROOT/ATTRIBUTIONS.md" "$GAME/docs/"
[ -x "$GAME/bin/crawl" ] || { echo "build first: scripts/build-crawl.sh"; exit 1; }

cat > "$GAME/run.sh" <<'RUN'
#!/bin/sh
# Starts Dungeon Crawl Stone Soup (tiles) on the MiSTer.  Extra arguments go to crawl.
# Optional settings go in /media/fat/dcss/env.sh:
#   MISTER_RESOLUTION=640x480|800x600 skip the resolution question and use this
#   MISTER_OUTPUT_MODE=off           do not change the HDMI mode (otherwise it follows the chosen resolution)
#   MISTER_RESTORE_MODE="<modeline>" mode to switch back to afterwards (default 1080p60)
D=/media/fat/dcss
cd "$D" || exit 1
[ -f "$D/env.sh" ] && . "$D/env.sh"
export HOME="$D"
mkdir -p "$D/saves" "$D/morgue"

# Ask every time unless env.sh selects a resolution. Accept the menu number or the resolution itself.
choose_resolution() {
    if [ -n "$MISTER_RESOLUTION" ]; then
        case "$MISTER_RESOLUTION" in
            640x480|800x600) RES=$MISTER_RESOLUTION; return 0 ;;
            *) echo "Unsupported resolution '$MISTER_RESOLUTION' (use 640x480 or 800x600)"; sleep 10; return 1 ;;
        esac
    fi
    while true; do
        echo
        echo "  Resolution for DCSS"
        echo "    1) 640x480"
        echo "    2) 800x600"
        printf "  Type 1 or 2, then Enter: "
        read -r answer || return 1
        case "$answer" in
            1|640x480) RES=640x480; return 0 ;;
            2|800x600) RES=800x600; return 0 ;;
        esac
    done
}
choose_resolution || exit 1

# The prebuilt level cache is only valid while the data files carry the exact timestamp it was built against.
# A zip stores local time, so unpacking can change it: set it again once, on the first run.
if [ ! -f "$D/saves/.mtimes-set" ]; then
    find "$D/dat" "$D/docs" "$D/settings" -exec touch -h -d "2026-01-01 00:00:00 UTC" {} + 2>/dev/null
    : > "$D/saves/.mtimes-set"
fi

# The scaler only scales the framebuffer by whole numbers, so switch the HDMI output itself to the
# game's resolution (the display scales it to fill the screen) and restore it afterwards.
MODE_640X480="640,16,96,48,480,10,2,33,25175,-hsync,-vsync"       # VESA 640x480 @ 60 Hz
MODE_800X600="800,40,128,88,600,1,4,23,40000,+hsync,+vsync"        # VESA 800x600 @ 60 Hz
MODE_1080P60="1920,88,44,148,1080,4,5,36,148500,+hsync,+vsync"     # CEA 1080p @ 60 Hz
case "$RES" in
    640x480) MODELINE=$MODE_640X480 ;;
    800x600) MODELINE=$MODE_800X600 ;;
esac
[ "$MISTER_OUTPUT_MODE" = off ] && MODELINE=""
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-mister}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
switched=0
if [ -n "$MODELINE" ] && [ -p /dev/MiSTer_cmd ]; then
    echo "video_mode $MODELINE" > /dev/MiSTer_cmd
    switched=1
    sleep 2.5   # let the display re-sync; Main resizes the framebuffer to match
fi
"$D/bin/crawl" -dir "$D" "$@" &
child=$!
trap 'kill -TERM $child 2>/dev/null' TERM HUP INT
wait $child
rc=$?
wait $child 2>/dev/null
if [ "$switched" = 1 ]; then
    echo "video_mode ${MISTER_RESTORE_MODE:-$MODE_1080P60}" > /dev/MiSTer_cmd
    sleep 1
fi
exit $rc
RUN
chmod +x "$GAME/run.sh"

# The level cache is validated against the exact mtime of each source file, and
# the SD card may round timestamps, so give every data file one fixed even
# timestamp, then build the cache here under qemu (the cache is 32-bit ARM
# format) instead of making the first launch spend minutes on it.
find "$GAME/dat" "$GAME/docs" "$GAME/settings" -exec touch -h -d "2026-01-01 00:00:00 UTC" {} +
mkdir -p "$GAME/saves" "$GAME/morgue"
( cd "$GAME" && time SDL_VIDEODRIVER=dummy qemu-arm bin/crawl -dir "$GAME" -builddb ) 2>&1 | tail -4
du -sh "$GAME/saves"

# Entry for the OSD Scripts menu (F12 > Scripts).
printf '#!/bin/bash\nexec /media/fat/dcss/run.sh "$@"\n' > "$OUT/Scripts/dcss.sh"
chmod +x "$OUT/Scripts/dcss.sh"
du -sh "$OUT"
