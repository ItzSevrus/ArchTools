# Wallshift

A small C++ wallpaper rotator for Linux/Wayland, using `awww` to apply wallpapers.

## Requirements

- C++17 compiler
- CMake
- `awww` and `awww-daemon` installed

Wallshift checks whether `awww-daemon` is already running and starts it automatically when needed.

On Arch Linux, install the build tools and wallpaper engine:

```bash
sudo pacman -S --needed base-devel cmake swww
```

Start the daemon in your Wayland session:

```bash
awww-daemon
```

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Run it:

```bash
./build/wallshift --help
```

## Usage

```bash
# Uses ~/Pictures/wallpapers; creates it if missing
wallshift --interval 5m --shuffle

# Random selection (can repeat the same image)
wallshift --dir ~/Pictures/Nature --interval 30s --random

# Apply one wallpaper and exit
wallshift --once
```

Intervals accept seconds (`30s`), minutes (`5m`), hours (`1h`), days (`1d`), or bare seconds (`300`).

Supported extensions: JPG/JPEG, PNG, WebP, BMP, GIF, TIFF, and AVIF. Images in subdirectories are included.

## Install

```bash
sudo cmake --install build
```

This installs the binary to the system's configured bindir (usually `/usr/local/bin`).

## Notes

- `--random` picks a new random file each rotation and may repeat images.
- `--shuffle` shuffles the collection and iterates through it.
- Wallshift starts `awww-daemon` automatically if it cannot find an existing daemon process.
- Run Wallshift inside your graphical Wayland session so the daemon inherits the required environment.
