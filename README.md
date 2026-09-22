# MiSTer-DCSS

[Dungeon Crawl Stone Soup](https://crawl.develz.org/) (DCSS), the open-source
roguelike, with its graphical tiles interface, running on the ARM (HPS) side of a
[MiSTer](https://github.com/MiSTer-devel) (DE10-Nano, dual Cortex-A9). The game
runs as an ordinary Linux program on the stock MiSTer system: nothing is installed
outside `/media/fat`, and the FPGA only shows the picture. This project supplies
the missing pieces: a cross-build of DCSS for the MiSTer's old userland, a software
renderer for the tiles interface (the MiSTer has no GPU, and DCSS's tiles build
only knows OpenGL), and a launcher that fills the screen.

DCSS needs no game data from anywhere else: the tiles, fonts and levels are part
of the game.

## What it does

- **DCSS 0.34.1 tiles, cross-built for the Cortex-A9** — one static ARM binary
  (about 12 MB), built on a PC with the Ubuntu ARM cross toolchain. Being static,
  it runs on the MiSTer's old root filesystem without changing it.
- **A software renderer for the tiles UI** — DCSS draws everything through a small
  wrapper that only asks for textured, alpha-blended rectangles and lines.
  `src/glwrapper-sw.cc` implements that wrapper on the CPU and draws straight into
  the SDL window surface, so no OpenGL is needed. Small patches in `patches/` make
  DCSS use it.
- **The MiSTer SDL2 video driver** — the same driver as
  [MiSTer-VCMI](https://github.com/aquasock/MiSTer-VCMI): it draws through
  `/dev/fb0`, waits for vertical sync on a separate thread, and reads the mouse and
  keyboard from the Linux input devices with USB hotplug.
- **A prebuilt level cache** — DCSS compiles its level and text databases on the
  first run, which takes about 90 seconds on the MiSTer. The bundle ships them
  already built (they are made on the PC under qemu), so the game starts in
  seconds.
- **A launcher for the OSD Scripts menu** — switches the HDMI output to 800x600 so
  your display scales the picture to fill the screen, runs the game, and restores
  your mode afterwards.

## Performance

Measured on a DE10-Nano MiSTer at 800x600. DCSS is turn-based and only redraws when
something happens, so this is comfortable.

| Situation | Result |
| --- | --- |
| Redraw after a move | about 65 ms of CPU |
| Idle | about 5% of one core |
| Start | under 15 seconds from launch to the title screen, including the 2.5 s mode switch |

## Requirements

- A MiSTer with a DE10-Nano (Cyclone V SoC), running the Menu core, with a MiSTer
  Linux image that has the `MiSTer_fb` device. Tested on the Buildroot image with
  Linux 6.18.38.
- A USB mouse and keyboard, and an HDMI display that accepts 800x600 at 60 Hz.
- To build: a Linux PC (Ubuntu 26.04 was used), about 3 GB of free disk space, a
  network connection for fetching sources, and a checkout of
  [MiSTer-VCMI](https://github.com/aquasock/MiSTer-VCMI) next to this repository:
  the SDL2 driver sources are shared, not copied (see [Building](#building)).

## Installation

### From a release

1. Download `MiSTer-DCSS-v<version>.zip` from the
   [Releases](https://github.com/aquasock/MiSTer-DCSS/releases) page and unzip it
   onto the root of the MiSTer's SD card, merging with what is there. This creates
   `/media/fat/dcss` and `/media/fat/Scripts/dcss.sh`. The location matters: the
   game finds its data under `/media/fat/dcss`.
2. On the MiSTer, open the OSD (F12), choose **Scripts**, and run **dcss**. The
   screen blinks as the output switches to 800x600, and the game starts. Quit from
   the game's own menu; the launcher switches your display back.

The zip also holds `INSTALL.txt`, the license texts in `LICENSES/`, and
`SOURCES.txt` listing the exact source versions and checksums. On the first
launch the launcher resets the timestamps of the data files (well under a second),
because the prebuilt level cache depends on them and unzipping can change them.

### From source

1. Build the bundle (see [Building](#building)).
2. Copy it to the MiSTer over SSH. `scripts/deploy.sh` logs in as `root` with the stock
   MiSTer password; edit it if yours differs.

   ```sh
   MISTER_HOST=<your MiSTer's IP> scripts/deploy.sh
   ```

   This installs the game to `/media/fat/dcss` and the launcher to
   `/media/fat/Scripts/dcss.sh`. It replaces the program and data but keeps your
   saves and any `env.sh`.
3. Launch it from the OSD as above.

To remove it, delete `/media/fat/dcss` and `/media/fat/Scripts/dcss.sh`.

## Configuration

Local settings go in `/media/fat/dcss/env.sh`, which the launcher reads if it
exists. Everything works without it.

| Setting | Meaning |
| --- | --- |
| `MISTER_OUTPUT_MODE=800x600` | The default: switch the HDMI output to 800x600 while playing |
| `MISTER_OUTPUT_MODE=off` | Do not change the HDMI mode |
| `MISTER_RESTORE_MODE="<modeline>"` | Mode to switch back to afterwards. Default is 1080p60 |

The modelines are `hact,hfp,hs,hbp,vact,vfp,vs,vbp,pixel-clock-kHz,hsync,vsync`,
the format Main_MiSTer's `video_mode` command takes.

DCSS's own options go in `/media/fat/dcss/init.txt`, which the game reads if it
exists; a commented template is in `/media/fat/dcss/settings/init.txt` and the
options are described in `/media/fat/dcss/docs/options_guide.txt`. Saves, character
dumps and the level cache are under `/media/fat/dcss/saves` and
`/media/fat/dcss/morgue`.

The SDL driver reads the `SDL_MISTER_*` environment variables described in the
[MiSTer-VCMI README](https://github.com/aquasock/MiSTer-VCMI#configuration); in
`env.sh` they need `export`.

## Current limitations

- **800x600 is the tested size.** The FPGA scaler only multiplies the framebuffer
  by whole numbers, so the launcher changes the HDMI mode and lets your display do
  the scaling.
- **No sound.** DCSS's sound support is not built.
- **The software renderer is simple.** It draws axis-aligned rectangles with
  nearest-neighbour sampling and does not implement texture filtering, so the
  `tile_filter_scaling` option has no effect.
- **Your original HDMI mode is not saved.** The MiSTer here has no `MiSTer.ini`, so
  the launcher restores 1080p60. Set `MISTER_RESTORE_MODE` if your display uses
  something else.
- **The console (text) version is not included.** It was built and worked, and was
  removed to keep the project to one game.
- **Not tested:** online play and the tutorial or sprint modes in depth.

## Building

Install the prerequisites on an Ubuntu (or Debian) PC:

```sh
sudo apt install gcc g++ make gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
    libc6-dev-armhf-cross cmake pkg-config patch qemu-user-binfmt git curl \
    python3 python3-yaml perl
```

Then, from the repository root, with MiSTer-VCMI checked out beside it (or
`SDL_DRIVER_DIR` pointing at its `sdl-driver` directory):

```sh
scripts/build-deps.sh    # zlib, libpng, FreeType, SDL2 with the MiSTer drivers, SDL2_image
scripts/build-crawl.sh   # fetches DCSS 0.34.1, applies patches/, builds the static binary
scripts/bundle.sh        # assembles work/bundle: binary, data, level cache, launcher
MISTER_HOST=<your MiSTer's IP> scripts/deploy.sh
```

Everything is created under `work/`, which is not tracked, and the pinned versions
are in `scripts/env.sh`. Each dependency step leaves a stamp, so a rerun skips
finished work; changing the SDL drivers rebuilds SDL automatically.
`scripts/build-crawl.sh` keeps an unstripped copy of the binary in
`work/debug/` for reading crash addresses.

`scripts/release.sh <version>` builds the release zip (`work/dist/`) from a fresh
bundle: it adds every license text and the source list, and writes `SHA256SUMS`.
Release notes live in `docs/release-notes/`. Run it from a committed tree, so that
`SOURCES.txt` records the commit.

## Source layout

- `scripts/` — `env.sh` (versions and paths), `toolchain.cmake`, `build-deps.sh`,
  `build-crawl.sh`, `bundle.sh` (also generates the launcher), `deploy.sh` and
  `release.sh`.
- `src/glwrapper-sw.cc`, `src/glwrapper-sw.h` — the software renderer.
- `patches/` — the changes to DCSS: they select the software renderer instead of
  OpenGL and stop the window code from creating a GL context.
- `work/` — created by the scripts: downloads, sources, build trees, the install
  prefix and the bundle. Not tracked.

## Documentation

- [Release notes](docs/release-notes/0.1.0.md)
- [Source attributions](ATTRIBUTIONS.md)
- [Upstream DCSS documentation](https://github.com/crawl/crawl/tree/master/crawl-ref/docs)
- [MiSTer-VCMI](https://github.com/aquasock/MiSTer-VCMI), which supplies the SDL2 driver

## License

Original project code is licensed GPL-2.0-or-later (see `LICENSE.txt`), the same
baseline as DCSS and MiSTer-VCMI. The complete
bundle is distributed under the same terms. DCSS, SDL, FreeType, glibc and the other
libraries keep their own licenses; see [ATTRIBUTIONS.md](ATTRIBUTIONS.md) for the
full inventory and the redistribution checklist.
