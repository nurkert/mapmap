#!/usr/bin/env bash
# build-deb.sh — package the built MapMap binary into a .deb.
#
# Layout:
#   /usr/bin/mapmap                              (binary)
#   /usr/share/mapmap/                           (translations + resources)
#   /usr/share/applications/mapmap.desktop
#   /usr/share/icons/hicolor/512x512/apps/mapmap.png
#   /usr/share/icons/hicolor/scalable/apps/mapmap.png  (best-effort)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PKG_NAME="mapmap"
PKG_VERSION="$(cat "$REPO_ROOT/VERSION.txt" 2>/dev/null || echo 0.0.0)"
OUTPUT_DIR="$REPO_ROOT/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    PKG_VERSION="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1;36m[deb]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[deb]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]]   || fail "Run on Linux."
command -v dpkg-deb >/dev/null   || fail "dpkg-deb missing (sudo apt install dpkg)"

BIN="$REPO_ROOT/mapmap"
[[ -x "$BIN" ]] || fail "Binary $BIN missing — build first via scripts/build-linux.sh"

case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l)  ARCH="armhf" ;;
    *)       ARCH="$(uname -m)" ;;
esac

mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d)"
trap "rm -rf '$STAGE'" EXIT

# ---------------------------------------------------------------------------
# Stage filesystem
# ---------------------------------------------------------------------------
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/$PKG_NAME" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/512x512/apps"

log "Copying binary + resources…"
install -m 0755 "$BIN" "$STAGE/usr/bin/$PKG_NAME"

# Translations (.qm files)
if compgen -G "$REPO_ROOT/translations/*.qm" >/dev/null; then
    mkdir -p "$STAGE/usr/share/$PKG_NAME/translations"
    cp "$REPO_ROOT/translations"/*.qm "$STAGE/usr/share/$PKG_NAME/translations/" || true
fi

# Examples (optional)
if [[ -d "$REPO_ROOT/examples" ]]; then
    cp -R "$REPO_ROOT/examples" "$STAGE/usr/share/$PKG_NAME/" 2>/dev/null || true
fi

# Icon
ICON_PNG="$STAGE/usr/share/icons/hicolor/512x512/apps/$PKG_NAME.png"
if command -v magick >/dev/null && [[ -f "$REPO_ROOT/resources/app_icons/mapmap.png" ]]; then
    magick "$REPO_ROOT/resources/app_icons/mapmap.png" -resize 512x512 "$ICON_PNG" 2>/dev/null \
        || cp "$REPO_ROOT/resources/app_icons/mapmap.png" "$ICON_PNG"
elif [[ -f "$REPO_ROOT/resources/app_icons/mapmap.png" ]]; then
    cp "$REPO_ROOT/resources/app_icons/mapmap.png" "$ICON_PNG"
fi

# Desktop entry
cat > "$STAGE/usr/share/applications/$PKG_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MapMap
GenericName=Video Mapping Software
Comment=Open source video mapping software
Exec=mapmap %F
Icon=mapmap
Terminal=false
Categories=AudioVideo;Video;Graphics;
Keywords=projection;video;mapping;mapper;
MimeType=application/x-mmp;
EOF

# ---------------------------------------------------------------------------
# Depends — minimal set; users get system Qt5 / GStreamer / liblo packages.
# ---------------------------------------------------------------------------
DEPENDS="libqt5core5a, libqt5gui5, libqt5widgets5, libqt5opengl5, libqt5multimedia5, libqt5xml5, libqt5network5, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, gstreamer1.0-libav, liblo7 | liblo7t64 | liblo-dev"

INSTALLED_KB="$(du -sk "$STAGE" | awk '{print $1}')"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Section: video
Priority: optional
Architecture: $ARCH
Maintainer: nurkert <noreply@nurkert.dev>
Installed-Size: $INSTALLED_KB
Depends: $DEPENDS
Recommends: gstreamer1.0-plugins-bad, gstreamer1.0-plugins-ugly
Homepage: https://github.com/nurkert/mapmap
Description: Open source video mapping software
 MapMap turns any surface into a projection canvas — distort and align
 videos and images onto walls, sculptures and live objects in real time.
 Built on Qt5, GStreamer and liblo for OSC control.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v gtk-update-icon-cache >/dev/null && \
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
command -v update-desktop-database >/dev/null && \
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------
DEB="$OUTPUT_DIR/${PKG_NAME}_${PKG_VERSION}_${ARCH}.deb"
log "Packaging $DEB…"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

log "Done. Install with:"
echo "  sudo dpkg -i $DEB && sudo apt-get install -f"
