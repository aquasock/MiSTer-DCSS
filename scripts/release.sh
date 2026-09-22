#!/usr/bin/env bash
# Builds the user-facing release archive from the bundle:  scripts/release.sh 0.1.0
#
#   work/dist/MiSTer-DCSS-v<version>.zip   unpack onto the root of the MiSTer's SD card
#   work/dist/SHA256SUMS
#   work/dist/RELEASE_NOTES-v<version>.md  (only if docs/release-notes/<version>.md exists)
#
# The archive holds dcss/ (game, data, prebuilt level cache, launcher, license texts, source list) and
# Scripts/dcss.sh. Run build-deps.sh and build-crawl.sh first; bundle.sh is run here to get a fresh bundle.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.1.0>}"
NAME="MiSTer-DCSS-v$VERSION"
DIST="$WORK/dist"
STAGE="$DIST/stage/$NAME"
CRAWL="$SRC/crawl"
CONTRIB="$CRAWL/crawl-ref/source/contrib"

# 1. Fresh bundle.
"$ROOT/scripts/bundle.sh" >/dev/null
rm -rf "$DIST/stage" "$DIST/$NAME.zip"
mkdir -p "$STAGE/dcss" "$STAGE/Scripts"

# 2. The game: the whole bundle (one binary, data, level cache, launcher). The bundle holds no saves or test tools.
cp -a "$WORK/bundle/dcss/." "$STAGE/dcss/"
rm -f "$STAGE/dcss/saves/.mtimes-set"          # the launcher sets the data timestamps again on the first run
cp -a "$WORK/bundle/Scripts/dcss.sh" "$STAGE/Scripts/"
echo "$VERSION" > "$STAGE/dcss/VERSION"

# 3. License texts of everything that ships, plus an index.
L="$STAGE/dcss/LICENSES"; mkdir -p "$L"
cp "$ROOT/LICENSE.txt" "$L/GPL-2.0.txt"
cp "$CRAWL/LICENSE" "$L/DCSS-LICENSE.txt"                                  # GPL-2.0 text plus the notice of other licenses
cp "$CRAWL/crawl-ref/docs/license/cc0.txt" "$L/CC0-1.0.txt"                # most DCSS tiles and art
cp "$CRAWL/crawl-ref/docs/license/lualicense.txt" "$L/Lua-MIT.txt"
cp "$CONTRIB/freetype/docs/GPLv2.TXT" "$L/FreeType-GPL-2.0.txt"
cp "$CONTRIB/freetype/docs/FTL.TXT" "$L/FreeType-FTL.txt"
cp "$ROOT/COPYING.ZLIB" "$L/SDL2-zlib.txt"
cp "$SRC/SDL2_image-$SDL2_IMAGE_VER/LICENSE.txt" "$L/SDL2_image-zlib.txt"
cp "$SRC/zlib-$ZLIB_VER/LICENSE" "$L/zlib.txt"
cp /usr/share/common-licenses/LGPL-2.1 "$L/glibc-LGPL-2.1.txt"
cp /usr/share/common-licenses/GPL-3 "$L/GPL-3.0.txt"                        # GCC runtime: GPL-3.0 with the exception below
cp /usr/share/doc/libc6-armhf-cross/copyright "$L/glibc-copyright.txt"
cp /usr/share/doc/libstdc++6/copyright "$L/GCC-runtime-libstdc++-copyright.txt"   # includes the GCC Runtime Library Exception
grep -q "GCC RUNTIME LIBRARY EXCEPTION" "$L/GCC-runtime-libstdc++-copyright.txt" || { echo "runtime exception text missing" >&2; exit 1; }
cat > "$L/SQLite-public-domain.txt" <<'TXT'
SQLite (version 3.8.7.1, from DCSS's contrib/sqlite) is in the public domain. The author disclaims copyright to the
source code; see https://www.sqlite.org/copyright.html
TXT
{
	printf 'DejaVu Sans and DejaVu Sans Mono 2.33 (dat/tiles/DejaVuSans.ttf, DejaVuSansMono.ttf)\n\n'
	# The license text as reproduced in Debian's copyright file: indented one space, blank lines written as " ."
	sed -n '/^Copyright: Copyright (c) 2003 by Bitstream/,/^Files: debian/p' /usr/share/doc/fonts-dejavu-core/copyright |
		sed -e '/^Files: debian/d' -e 's/^Copyright: //' -e 's/^ \.$//' -e 's/^ //'
} > "$L/DejaVu-Bitstream-Vera.txt"
grep -q "THE FONT SOFTWARE IS PROVIDED" "$L/DejaVu-Bitstream-Vera.txt" || { echo "could not extract the Bitstream Vera text" >&2; exit 1; }
cat > "$L/README.txt" <<'TXT'
Licenses of the software in this package. See ATTRIBUTIONS.md for what each component is used for.

  GPL-2.0.txt                            MiSTer-DCSS's own code (GPL-2.0-or-later); the whole package is GPL-2.0-or-later
  DCSS-LICENSE.txt                       Dungeon Crawl Stone Soup (GPL-2.0-or-later, and the notice of other licenses in it)
  CC0-1.0.txt                            most of DCSS's tiles and artwork (see https://github.com/crawl/tiles for the rest)
  Lua-MIT.txt, SQLite-public-domain.txt  Lua and SQLite, built into the game
  FreeType-GPL-2.0.txt, FreeType-FTL.txt FreeType, built into the game (used under its GPL-2.0 option)
  SDL2-zlib.txt, SDL2_image-zlib.txt     SDL2 (with the MiSTer drivers) and SDL2_image, built into the game
  zlib.txt                               zlib, built into the game
  DejaVu-Bitstream-Vera.txt              DejaVu fonts in dat/tiles
  glibc-LGPL-2.1.txt, glibc-copyright.txt   the C library linked statically into bin/crawl
  GCC-runtime-libstdc++-copyright.txt,
  GPL-3.0.txt                            libstdc++ and libgcc linked statically (GPL-3.0 with the GCC Runtime Library Exception)

stb_image (public domain or MIT), nanosvg (zlib) and qoi (MIT) are part of SDL2_image.
TXT
cp "$ROOT/README.md" "$ROOT/ATTRIBUTIONS.md" "$STAGE/dcss/"
cp "$ROOT/LICENSE.txt" "$ROOT/COPYING.ZLIB" "$STAGE/dcss/"

# 4. Where the corresponding source comes from, with checksums of the exact archives used.
DRIVER_REPO="$(git -C "$SDL_DRIVER_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
{
	echo "MiSTer-DCSS v$VERSION: corresponding source"
	echo
	echo "This package's own source: https://github.com/aquasock/MiSTer-DCSS"
	if git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
		echo "  commit $(git -C "$ROOT" rev-parse HEAD)$(git -C "$ROOT" diff --quiet HEAD -- 2>/dev/null || echo ' (built with uncommitted changes)')"
	fi
	echo "  scripts/env.sh pins every version below; scripts/build-deps.sh and build-crawl.sh fetch and build them."
	echo
	echo "SDL2 video and audio drivers: https://github.com/aquasock/MiSTer-VCMI (sdl-driver/)"
	[ -n "$DRIVER_REPO" ] && echo "  commit $(git -C "$DRIVER_REPO" rev-parse HEAD)$(git -C "$DRIVER_REPO" diff --quiet HEAD -- sdl-driver 2>/dev/null || echo ' (built with uncommitted changes)')"
	echo
	echo "Dungeon Crawl Stone Soup $CRAWL_TAG: https://github.com/crawl/crawl (tag $CRAWL_TAG)"
	echo "  commit $(git -C "$CRAWL" rev-parse HEAD)"
	echo "  plus the patches in patches/ and the software renderer in src/ of this project"
	for d in lua sqlite freetype fonts; do
		echo "  submodule contrib/$d: commit $(git -C "$CONTRIB/$d" rev-parse HEAD)"
	done
	echo
	echo "Libraries (sha256 of the archives that were built):"
	for f in "SDL2-$SDL2_VER.tar.gz" "SDL2_image-$SDL2_IMAGE_VER.tar.gz" "zlib-$ZLIB_VER.tar.gz" "libpng-$LIBPNG_VER.tar.gz"; do
		printf '  %s  %s\n' "$(sha256sum "$DL/$f" | cut -d' ' -f1)" "$f"
	done
	echo "  (SDL2, SDL2_image: https://github.com/libsdl-org, with the sdl-driver patches and drivers applied;"
	echo "   zlib: https://github.com/madler/zlib; libpng is only used to pack the tile sheets on the build machine)"
	echo
	echo "C runtime linked into bin/crawl: glibc $(dpkg-query -W -f='${Version}' libc6-dev-armhf-cross), Ubuntu (source package glibc;"
	echo "  the cross packages come from source package cross-toolchain-base)."
	echo "C++ runtime: GCC $(arm-linux-gnueabihf-gcc -dumpfullversion), Ubuntu (source package gcc-15-cross)."
	echo
	echo "LGPL/GPL note: bin/crawl is statically linked, so to replace the C library you relink it. The object files are built"
	echo "by scripts/build-crawl.sh from the source listed here; changing the toolchain's libc and running the script again"
	echo "produces a program that uses it. On request, the source for any GPL or LGPL component listed here can also be"
	echo "obtained from the project page above."
} > "$STAGE/dcss/SOURCES.txt"

# 5. Instructions for people who only download the zip.
cat > "$STAGE/dcss/INSTALL.txt" <<TXT
MiSTer-DCSS v$VERSION: installing

1. Copy the two folders from this zip onto the root of your MiSTer's SD card, merging with what is there:
       dcss/     ->  /media/fat/dcss
       Scripts/  ->  /media/fat/Scripts
   The location matters: the game looks for its data in /media/fat/dcss.

2. On the MiSTer press F12, choose Scripts, and run "dcss".
   The screen blinks as the HDMI output switches to 800x600 (your display scales it to fill the screen).
   Quit from the game's own menu; the display is switched back to 1080p60.

No game data is needed: the tiles, fonts and levels are part of Dungeon Crawl Stone Soup.

On the first launch the launcher sets the timestamps of the data files again (well under a second): the prebuilt level
cache depends on them, and unzipping can change them. Do not remove saves/db and saves/des: without them the game
rebuilds the cache (about 90 seconds).

Needs: a MiSTer with a DE10-Nano, a USB mouse and keyboard, and an HDMI display that accepts 800x600 at 60 Hz.
Saves, character dumps and settings are kept in /media/fat/dcss/saves and /media/fat/dcss/morgue; your own game
options go in /media/fat/dcss/init.txt (a template is in settings/init.txt).

To remove: delete /media/fat/dcss and /media/fat/Scripts/dcss.sh.
More: README.md, and the license texts in LICENSES/ (see ATTRIBUTIONS.md).
TXT

# 6. Pack it, keeping the layout at the top level.
python3 - "$STAGE" "$DIST/$NAME.zip" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1:3]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(stage):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(root, f)
            arc = os.path.relpath(full, stage)
            info = zipfile.ZipInfo.from_file(full, arc)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as fh:
                z.writestr(info, fh.read(), zipfile.ZIP_DEFLATED, 9)
PY
( cd "$DIST" && sha256sum "$NAME.zip" > SHA256SUMS )
[ -f "$ROOT/docs/release-notes/$VERSION.md" ] && cp "$ROOT/docs/release-notes/$VERSION.md" "$DIST/RELEASE_NOTES-v$VERSION.md"
echo "built $DIST/$NAME.zip ($(du -h "$DIST/$NAME.zip" | cut -f1))"
