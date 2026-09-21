#!/bin/bash
# Cross-builds the graphical (tiles) Dungeon Crawl Stone Soup as one static armhf
# binary, software-rendered through the MiSTer SDL2 driver.
# The result is staged in work/stage/dcss (bin/crawl, data in dat/ docs/ settings/).
set -euo pipefail
. "$(dirname "$0")/env.sh"

CRAWL="$SRC/crawl"
S="$CRAWL/crawl-ref/source"
[ -d "$CRAWL/.git" ] || git clone --depth 1 --branch "$CRAWL_TAG" \
    https://github.com/crawl/crawl.git "$CRAWL"
git -C "$CRAWL" submodule update --init --depth 1 \
    crawl-ref/source/contrib/lua crawl-ref/source/contrib/sqlite \
    crawl-ref/source/contrib/freetype crawl-ref/source/contrib/fonts

# Patches to DCSS (idempotent), and the software GL backend, which is new source.
for p in "$ROOT"/patches/*.patch; do
    git -C "$CRAWL" apply --reverse --check "$p" 2>/dev/null || git -C "$CRAWL" apply "$p"
done
cp "$ROOT"/src/glwrapper-sw.* "$S/"

# pkg-config for the armhf prefix (the Makefile picks up <triplet>-pkg-config).
mkdir -p "$TOOLS/bin"
cat >"$TOOLS/bin/$CROSS-pkg-config" <<PKG
#!/bin/sh
export PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
exec /usr/bin/pkg-config --static "\$@"
PKG
chmod +x "$TOOLS/bin/$CROSS-pkg-config"
# The tile packer runs on this machine and links libpng statically, so it needs
# libpng's private libraries (zlib) on its link line: make plain pkg-config imply --static.
printf '#!/bin/sh\nexec /usr/bin/pkg-config --static "$@"\n' >"$TOOLS/bin/pkg-config"
chmod +x "$TOOLS/bin/pkg-config"
export PATH="$TOOLS/bin:$PATH"

STAGE="$WORK/stage"
mkdir -p "$STAGE/dcss/bin"
DEVICE_DIR=/media/fat/dcss

# The tile sheets are packed on the build machine, which needs its own libpng.
export PKG_CONFIG_PATH="$HOSTPREFIX/lib/pkgconfig"
FLAGS=(CROSSHOST=$CROSS TILES=y SWGL=y
    EXTERNAL_FLAGS_L="$ARCH_FLAGS -isystem $PREFIX/include" EXTERNAL_FLAGS="$ARCH_FLAGS"
    EXTERNAL_LDFLAGS="-static -L$PREFIX/lib"
    MONOSPACED_FONT="$DEVICE_DIR/dat/tiles/DejaVuSansMono.ttf"
    PROPORTIONAL_FONT="$DEVICE_DIR/dat/tiles/DejaVuSans.ttf")

cd "$S"
# No DATADIR/SAVEDIR is compiled in: the game finds its data under the
# directory given with -dir, so the same tree works on the PC (to build the
# level cache under qemu) and on the MiSTer. Static link: the target's glibc
# (2.31) is older than the toolchain's.
make -j"$JOBS" "${FLAGS[@]}" crawl >"$LOGS/crawl-build.log" 2>&1 \
    || { grep -n -E " error |\*\*\*|undefined reference" "$LOGS/crawl-build.log" | head -20; exit 1; }
mkdir -p "$WORK/debug"; cp crawl "$WORK/debug/crawl"    # unstripped, for symbolising crash addresses
$CROSS-strip -o "$STAGE/dcss/bin/crawl" crawl

# Data files, including the tile sheets and fonts.
make "${FLAGS[@]}" DESTDIR="$STAGE/dcss" prefix=/ DATADIR=/ install-data \
    >"$LOGS/crawl-install.log" 2>&1 || { tail -20 "$LOGS/crawl-install.log"; exit 1; }
mkdir -p "$STAGE/dcss/dat/tiles"
cp contrib/fonts/DejaVuSans.ttf contrib/fonts/DejaVuSansMono.ttf "$STAGE/dcss/dat/tiles/"
ls -la "$STAGE/dcss/bin"
