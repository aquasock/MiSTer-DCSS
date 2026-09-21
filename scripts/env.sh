# Shared settings for the MiSTer-DCSS cross build. Source this file.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
DL="$WORK/dl"
SRC="$WORK/src"
BUILD="$WORK/build"
LOGS="$WORK/logs"
PREFIX="$WORK/prefix"          # armhf install prefix for dependencies
CROSS=arm-linux-gnueabihf
JOBS="${JOBS:-$(nproc)}"

CRAWL_TAG=0.34.1

ARCH_FLAGS="-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard"
mkdir -p "$DL" "$SRC" "$BUILD" "$LOGS" "$PREFIX"

ZLIB_VER=1.3.1
LIBPNG_VER=1.6.44
SDL2_VER=2.32.10
SDL2_IMAGE_VER=2.8.12
# The MiSTer SDL2 video/audio drivers and their patches come from MiSTer-VCMI.
SDL_DRIVER_DIR="${SDL_DRIVER_DIR:-$ROOT/../MiSTer-VCMI/sdl-driver}"
HOSTPREFIX="$WORK/hostprefix"  # x86 libpng, only for the tile-sheet packer (rltiles)
TOOLS="$WORK/tools"
