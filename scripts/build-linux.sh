#!/usr/bin/env bash
# build-linux.sh — install dependencies and build MapMap on Linux.
#
# Usage:
#   scripts/build-linux.sh            # configure + build (Release)
#   scripts/build-linux.sh --debug    # debug build
#   scripts/build-linux.sh --clean    # make distclean first
#   scripts/build-linux.sh --deb      # also produce a .deb in dist/
#   scripts/build-linux.sh --run      # build then launch ./mapmap
#
# Idempotent. Detects apt / dnf / pacman.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG="release"
DO_CLEAN=0
WITH_DEB=0
RUN_AFTER=0

for arg in "$@"; do
    case "$arg" in
        --debug)   CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        --clean)   DO_CLEAN=1 ;;
        --deb)     WITH_DEB=1 ;;
        --run)     RUN_AFTER=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown flag: $arg" >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1;36m[build-linux]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build-linux]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[build-linux]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || fail "This script targets Linux."

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
install_apt() {
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        build-essential pkg-config git \
        qtbase5-dev qttools5-dev qttools5-dev-tools \
        libqt5opengl5-dev libqt5multimedia5-plugins qtmultimedia5-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav gstreamer1.0-tools \
        liblo-dev \
        dpkg-dev fakeroot imagemagick
}

install_dnf() {
    sudo dnf install -y \
        gcc-c++ make pkgconf git \
        qt5-qtbase-devel qt5-qttools-devel qt5-qtmultimedia-devel \
        gstreamer1-devel gstreamer1-plugins-base-devel \
        gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly-free \
        gstreamer1-libav \
        liblo-devel \
        dpkg fakeroot ImageMagick
}

install_pacman() {
    sudo pacman -S --needed --noconfirm \
        base-devel pkgconf git \
        qt5-base qt5-tools qt5-multimedia \
        gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav \
        liblo \
        dpkg fakeroot imagemagick
}

if command -v apt-get >/dev/null; then
    log "Detected apt → installing dependencies (sudo)…"
    install_apt
elif command -v dnf >/dev/null; then
    log "Detected dnf → installing dependencies (sudo)…"
    install_dnf
elif command -v pacman >/dev/null; then
    log "Detected pacman → installing dependencies (sudo)…"
    install_pacman
else
    warn "Unknown package manager — please install Qt5, GStreamer 1.0 and liblo manually."
fi

QMAKE="$(command -v qmake-qt5 || command -v qmake6 || command -v qmake)"
[[ -n "$QMAKE" ]] || fail "qmake not on PATH after installing dependencies."

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if [[ $DO_CLEAN -eq 1 ]]; then
    log "Cleaning…"
    make distclean >/dev/null 2>&1 || true
    rm -f Makefile
fi

log "Running qmake (CONFIG=$CONFIG)…"
"$QMAKE" -config "$CONFIG" mapmap.pro

JOBS="$(nproc 2>/dev/null || echo 4)"
log "Compiling (-j$JOBS)…"
make -j"$JOBS"

[[ -x "$REPO_ROOT/mapmap" ]] || fail "Build finished but ./mapmap binary is missing."

log "Build succeeded → $REPO_ROOT/mapmap"

if [[ $WITH_DEB -eq 1 ]]; then
    log "Building .deb…"
    "$SCRIPT_DIR/build-deb.sh"
fi

if [[ $RUN_AFTER -eq 1 ]]; then
    log "Launching MapMap…"
    exec "$REPO_ROOT/mapmap"
fi
