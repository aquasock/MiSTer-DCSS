#!/bin/bash
# Builds the libraries the target lacks (all static): zlib, libpng, FreeType,
# SDL2 (with the MiSTer drivers) and SDL2_image.  Usage: build-deps.sh [step...]
set -euo pipefail
. "$(dirname "$0")/env.sh"

export DCSS_PREFIX="$PREFIX"
CONTRIB="$SRC/crawl/crawl-ref/source/contrib"
# FreeType comes from DCSS's own contrib submodule.
[ -d "$SRC/crawl/.git" ] || git clone --depth 1 --branch "$CRAWL_TAG" https://github.com/crawl/crawl.git "$SRC/crawl"
git -C "$SRC/crawl" submodule update --init --depth 1 crawl-ref/source/contrib/freetype

extract() {  # extract TARBALL DIR
    [ -d "$SRC/$2" ] || tar -C "$SRC" -xf "$DL/$1"
}

# cmake helper: cm NAME SRCDIR [args...] builds and installs into $PREFIX.
cm() {
    local name=$1 src=$2; shift 2
    local stamp="$BUILD/$name.stamp"
    [ -f "$stamp" ] && { echo "$name already built"; return 0; }
    rm -rf "$BUILD/$name"
    cmake -S "$src" -B "$BUILD/$name" -DCMAKE_TOOLCHAIN_FILE="$ROOT/scripts/toolchain.cmake" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_C_FLAGS_RELEASE="-O2" -DCMAKE_CXX_FLAGS_RELEASE="-O2" "$@" >"$LOGS/$name-configure.log" 2>&1 \
        || { tail -20 "$LOGS/$name-configure.log"; return 1; }
    cmake --build "$BUILD/$name" -j"$JOBS" >"$LOGS/$name-build.log" 2>&1 || { tail -20 "$LOGS/$name-build.log"; return 1; }
    cmake --install "$BUILD/$name" >"$LOGS/$name-install.log" 2>&1
    touch "$stamp"; echo "$name installed"
}

step_zlib() {
    local tar="$DL/zlib-$ZLIB_VER.tar.gz"
    [ -f "$tar" ] || curl -fL -o "$tar" "https://zlib.net/fossils/zlib-$ZLIB_VER.tar.gz"
    extract "zlib-$ZLIB_VER.tar.gz" "zlib-$ZLIB_VER"
    cm zlib "$SRC/zlib-$ZLIB_VER" -DBUILD_SHARED_LIBS=OFF
    rm -f "$PREFIX"/lib/libz.so*        # link the static library
}

fetch_libpng() {
    local tar="$DL/libpng-$LIBPNG_VER.tar.gz"
    [ -f "$tar" ] || curl -fL -o "$tar" "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VER.tar.gz"
    extract "libpng-$LIBPNG_VER.tar.gz" "libpng-$LIBPNG_VER"
}

step_libpng() {
    fetch_libpng
    cm libpng "$SRC/libpng-$LIBPNG_VER" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
        -DPNG_ARM_NEON=off -DZLIB_ROOT="$PREFIX"
}

# The x86 build of libpng that the tile-sheet packer needs on the build machine.
step_hostpng() {
    [ -f "$BUILD/hostpng.stamp" ] && { echo "hostpng already built"; return 0; }
    fetch_libpng
    rm -rf "$BUILD/hostpng"
    cmake -S "$SRC/libpng-$LIBPNG_VER" -B "$BUILD/hostpng" -DCMAKE_INSTALL_PREFIX="$HOSTPREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
        >"$LOGS/hostpng-configure.log" 2>&1 && cmake --build "$BUILD/hostpng" -j"$JOBS" >"$LOGS/hostpng-build.log" 2>&1 \
        && cmake --install "$BUILD/hostpng" >"$LOGS/hostpng-install.log" 2>&1 || { tail -20 "$LOGS"/hostpng-*.log; return 1; }
    touch "$BUILD/hostpng.stamp"; echo "hostpng installed"
}

step_freetype() {
    cm freetype "$CONTRIB/freetype" -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_BROTLI=ON \
        -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON -DFT_REQUIRE_ZLIB=ON -DZLIB_ROOT="$PREFIX"
    # FreeType's cmake build does not install a pkg-config file, which DCSS's Makefile wants.
    mkdir -p "$PREFIX/lib/pkgconfig"
    cat >"$PREFIX/lib/pkgconfig/freetype2.pc" <<PC
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: FreeType 2
Description: A free, high-quality, and portable font engine.
Version: 26.0.20
Requires.private: zlib
Libs: -L\${libdir} -lfreetype
Libs.private: -lz -lm
Cflags: -I\${includedir}/freetype2
PC
}

step_sdl2() {
    extract "SDL2-$SDL2_VER.tar.gz" "SDL2-$SDL2_VER"
    local d="$SRC/SDL2-$SDL2_VER" dd="$SDL_DRIVER_DIR"
    [ -d "$dd/mister" ] || { echo "SDL driver sources not found in $dd (set SDL_DRIVER_DIR)"; return 1; }
    # Register the MiSTer drivers in SDL (fresh tree when the hooks change), then add their sources.
    if ! grep -q SDL_MISTERAUDIO "$d/CMakeLists.txt"; then
        rm -rf "$d"; extract "SDL2-$SDL2_VER.tar.gz" "SDL2-$SDL2_VER"
        patch -s -d "$d" -p1 <"$dd/sdl2-mister-hooks.patch"
    fi
    grep -q "division-free resampler" "$d/src/audio/SDL_audiocvt.c" || patch -s -d "$d" -p1 <"$dd/sdl2-resampler.patch"
    mkdir -p "$d/src/video/mister" "$d/src/audio/mister"
    cp "$dd"/mister/* "$d/src/video/mister/"; cp "$dd"/mister-audio/* "$d/src/audio/mister/"
    local h; h=$(cat "$dd"/mister/* "$dd"/mister-audio/* "$dd"/*.patch | md5sum | cut -d' ' -f1)
    [ "$(cat "$BUILD/sdl2.driver" 2>/dev/null)" = "$h" ] || { rm -f "$BUILD/sdl2.stamp"; echo "$h" >"$BUILD/sdl2.driver"; }
    cm sdl2 "$d" -DSDL_MISTER=ON -DSDL_MISTERAUDIO=ON \
        -DBUILD_SHARED_LIBS=OFF -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_TEST=OFF \
        -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_VULKAN=OFF -DSDL_OPENGL=OFF \
        -DSDL_OPENGLES=OFF -DSDL_RPI=OFF -DSDL_VIVANTE=OFF -DSDL_OFFSCREEN=ON \
        -DSDL_ALSA=OFF -DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF -DSDL_SNDIO=OFF \
        -DSDL_OSS=OFF -DSDL_ESD=OFF -DSDL_ARTS=OFF -DSDL_NAS=OFF \
        -DSDL_DBUS=OFF -DSDL_IBUS=OFF -DSDL_LIBUDEV=OFF -DSDL_HIDAPI=OFF -DSDL_HIDAPI_LIBUSB=OFF \
        -DSDL_LIBSAMPLERATE=OFF -DSDL_CCACHE=OFF
}

step_sdl2_image() {
    extract "SDL2_image-$SDL2_IMAGE_VER.tar.gz" "SDL2_image-$SDL2_IMAGE_VER"
    cm sdl2_image "$SRC/SDL2_image-$SDL2_IMAGE_VER" -DBUILD_SHARED_LIBS=OFF -DSDL2_DIR="$PREFIX/lib/cmake/SDL2" \
        -DSDL2IMAGE_VENDORED=OFF -DSDL2IMAGE_DEPS_SHARED=OFF -DSDL2IMAGE_BACKEND_STB=ON \
        -DSDL2IMAGE_AVIF=OFF -DSDL2IMAGE_JXL=OFF -DSDL2IMAGE_TIF=OFF -DSDL2IMAGE_WEBP=OFF \
        -DSDL2IMAGE_JPG=OFF -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF
}

ALL=(zlib libpng hostpng freetype sdl2 sdl2_image)
for s in "${@:-${ALL[@]}}"; do "step_$s"; done
