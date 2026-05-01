#!/usr/bin/env bash
# Install MapMap from a freshly wiped macOS (Apple Silicon or Intel).
#
# What it does:
#   1. Ensures Xcode Command Line Tools are present.
#   2. Installs Homebrew if missing.
#   3. Installs build dependencies (qt@5, gstreamer, liblo, pkg-config).
#   4. Builds MapMap with qmake + make.
#   5. Bundles the .app with macdeployqt.
#   6. Copies MapMap.app to /Applications.
#
# Usage:
#   ./scripts/install-macos.sh           # build + install to /Applications
#   ./scripts/install-macos.sh --no-install   # build only, do not copy to /Applications
#   ./scripts/install-macos.sh --clean        # run `make distclean` before building

set -euo pipefail

# ---- options --------------------------------------------------------------
DO_INSTALL=1
DO_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --no-install) DO_INSTALL=0 ;;
    --clean)      DO_CLEAN=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# ---- helpers --------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# ---- preflight ------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  die "This script is for macOS only."
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
log "Project root: $PROJECT_ROOT"

# ---- 1) Xcode Command Line Tools ------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (a GUI dialog will appear)..."
  xcode-select --install || true
  warn "Wait for the Xcode Command Line Tools install to finish, then re-run this script."
  exit 1
fi
log "Xcode Command Line Tools: $(xcode-select -p)"

# ---- 2) Homebrew ----------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make sure brew is on PATH for this shell, both Apple Silicon and Intel.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
command -v brew >/dev/null 2>&1 || die "Homebrew is not on PATH after install."
log "Using Homebrew at: $(command -v brew)"

# ---- 3) Build dependencies ------------------------------------------------
log "Installing build dependencies (qt@5, gstreamer, liblo, pkg-config)..."
brew install qt@5 gstreamer liblo pkg-config

QT_PREFIX="$(brew --prefix qt@5)"
GST_PREFIX="$(brew --prefix gstreamer)"
LIBLO_PREFIX="$(brew --prefix liblo)"
log "Qt5 prefix:       $QT_PREFIX"
log "GStreamer prefix: $GST_PREFIX"
log "liblo prefix:     $LIBLO_PREFIX"

# qt@5 is keg-only, so put its bin (qmake, lrelease, macdeployqt) on PATH first.
export PATH="$QT_PREFIX/bin:$PATH"

# Make sure pkg-config can find liblo (some versions ship .pc into a subdir).
export PKG_CONFIG_PATH="$LIBLO_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# ---- 4) Build -------------------------------------------------------------
if (( DO_CLEAN )); then
  log "Running make distclean..."
  make distclean >/dev/null 2>&1 || true
  rm -f Makefile
fi

log "Running qmake..."
qmake -config release mapmap.pro

log "Compiling (this may take a few minutes)..."
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make -j"$JOBS"

[[ -d "$PROJECT_ROOT/MapMap.app" ]] || die "Build finished but MapMap.app was not produced."

# ---- 5) Bundle Qt + custom Info.plist + icon ------------------------------
log "Bundling Qt frameworks with macdeployqt..."
macdeployqt MapMap.app

if [[ -f resources/macOS/info.plist ]]; then
  cp -f resources/macOS/info.plist MapMap.app/Contents/Info.plist
fi
if [[ -f resources/macOS/mapmap.icns ]]; then
  cp -f resources/macOS/mapmap.icns MapMap.app/Contents/Resources/
fi

# macdeployqt rewrites install_name paths on every dylib/framework, which
# invalidates the linker's ad-hoc signature. macOS 26+ kills any binary with
# an invalid signature on launch (SIGKILL, Code Signature Invalid). Re-sign
# everything ad-hoc so the bundle launches without a Developer ID.
log "Re-signing bundle (ad-hoc) for macOS 26+ code-signing enforcement..."
find MapMap.app -type f \( \
       -name "*.dylib" -o -name "*.so" \
    \) -exec codesign --force --timestamp=none --sign - {} +
find MapMap.app -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
  codesign --force --timestamp=none --sign - "$fw"
done
codesign --force --timestamp=none --sign - MapMap.app/Contents/MacOS/MapMap
codesign --force --timestamp=none --sign - MapMap.app

# ---- 6) Install to /Applications -----------------------------------------
if (( DO_INSTALL )); then
  log "Installing to /Applications/MapMap.app (sudo may prompt)..."
  if [[ -d /Applications/MapMap.app ]]; then
    sudo rm -rf /Applications/MapMap.app
  fi
  sudo cp -R MapMap.app /Applications/
  log "Installed: /Applications/MapMap.app"
fi

log "Done."
echo
echo "Run from Finder, or from a terminal:"
echo "  open -a MapMap"
echo
echo "If GStreamer plugins fail to load at runtime, try:"
echo "  GST_PLUGIN_PATH=\"$GST_PREFIX/lib/gstreamer-1.0\" open -a MapMap"
