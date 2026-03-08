#!/usr/bin/env bash
# build_appimage.sh — builds Anyfile and packages it as an AppImage
# Usage: ./scripts/build_appimage.sh [--debug] [--no-tests]
#
# Requirements (auto-downloaded if missing):
#   linuxdeploy-x86_64.AppImage
#   linuxdeploy-plugin-qt-x86_64.AppImage
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build/linux"
APPDIR="$BUILD_DIR/AppDir"
TOOLS_DIR="$ROOT_DIR/build/tools"
DIST_DIR="$ROOT_DIR/dist"

# ── Parse flags ───────────────────────────────────────────────────────────────
BUILD_TYPE=Release
BUILD_TESTS=OFF

for arg in "$@"; do
    case "$arg" in
        --debug)    BUILD_TYPE=Debug ;;
        --tests)    BUILD_TESTS=ON   ;;
        --no-tests) BUILD_TESTS=OFF  ;;
    esac
done

# ── Detect arch ───────────────────────────────────────────────────────────────
ARCH="$(uname -m)"
LINUXDEPLOY="$TOOLS_DIR/linuxdeploy-$ARCH.AppImage"
LINUXDEPLOY_QT="$TOOLS_DIR/linuxdeploy-plugin-qt-$ARCH.AppImage"

echo ""
echo "┌─ AppImage Build Config ──────────────────────┐"
echo "│  Type  : $BUILD_TYPE"
echo "│  Arch  : $ARCH"
echo "│  Tests : $BUILD_TESTS"
echo "└──────────────────────────────────────────────┘"
echo ""

# ── Download linuxdeploy tools if needed ──────────────────────────────────────
mkdir -p "$TOOLS_DIR"

if [ ! -f "$LINUXDEPLOY" ]; then
    echo "Downloading linuxdeploy..."
    curl -fsSL -o "$LINUXDEPLOY" \
        "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage"
    chmod +x "$LINUXDEPLOY"
fi

if [ ! -f "$LINUXDEPLOY_QT" ]; then
    echo "Downloading linuxdeploy-plugin-qt..."
    curl -fsSL -o "$LINUXDEPLOY_QT" \
        "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$ARCH.AppImage"
    chmod +x "$LINUXDEPLOY_QT"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Configuring..."
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_GUI=ON \
    -DBUILD_TESTS="$BUILD_TESTS"

echo "Building..."
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

# ── Assemble AppDir ───────────────────────────────────────────────────────────
echo "Assembling AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/applications"

# Binaries
cp "$BUILD_DIR/bin/anyfile_gui" "$APPDIR/usr/bin/anyfile_gui"
if [ -f "$BUILD_DIR/bin/anyfile" ]; then
    cp "$BUILD_DIR/bin/anyfile" "$APPDIR/usr/bin/anyfile"
fi

# Icons
cp "$ROOT_DIR/src/gui/resources/icons/app.svg" \
    "$APPDIR/usr/share/icons/hicolor/scalable/apps/anyfile.svg"
cp "$ROOT_DIR/src/gui/resources/icons/app.png" \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps/anyfile.png"
# AppImage also expects the icon at the root
cp "$ROOT_DIR/src/gui/resources/icons/app.png" "$APPDIR/anyfile.png"

# Desktop file
cp "$ROOT_DIR/linux/anyfile.desktop" "$APPDIR/usr/share/applications/anyfile.desktop"
cp "$ROOT_DIR/linux/anyfile.desktop" "$APPDIR/anyfile.desktop"

# ── Bundle Qt and system libs via linuxdeploy ─────────────────────────────────
echo "Bundling dependencies..."
mkdir -p "$DIST_DIR"

# Tell linuxdeploy-plugin-qt where to find QML files compiled into the binary
# (QML is compiled in via qt_add_qml_module so no external QML dir needed)
export QML_SOURCES_PATHS="$ROOT_DIR/src/gui/qml"
export QMAKE="$(which qmake6 2>/dev/null || which qmake)"

# Run linuxdeploy with Qt plugin
"$LINUXDEPLOY" \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/anyfile_gui" \
    --desktop-file "$APPDIR/anyfile.desktop" \
    --icon-file "$APPDIR/anyfile.png" \
    --plugin qt \
    --output appimage

# Move output to dist/
APPIMAGE_FILE="$(ls Anyfile*.AppImage 2>/dev/null | head -1)"
if [ -n "$APPIMAGE_FILE" ]; then
    mv "$APPIMAGE_FILE" "$DIST_DIR/"
    echo ""
    echo "AppImage ready → $DIST_DIR/$APPIMAGE_FILE"
else
    # linuxdeploy sometimes names it differently
    APPIMAGE_FILE="$(ls *.AppImage 2>/dev/null | grep -v linuxdeploy | head -1)"
    if [ -n "$APPIMAGE_FILE" ]; then
        mv "$APPIMAGE_FILE" "$DIST_DIR/"
        echo ""
        echo "AppImage ready → $DIST_DIR/$APPIMAGE_FILE"
    else
        echo "Build succeeded but AppImage file not found in current directory."
        echo "Check above output for the output path."
    fi
fi

# ── Bundle libmagic if needed (not always auto-detected) ─────────────────────
LIBMAGIC="$(ldconfig -p 2>/dev/null | grep 'libmagic\.so' | awk '{print $NF}' | head -1)"
if [ -n "$LIBMAGIC" ] && [ -f "$APPDIR/usr/lib" ]; then
    cp "$LIBMAGIC" "$APPDIR/usr/lib/" 2>/dev/null || true
    # Also copy magic database
    if [ -d "/usr/share/misc" ] && [ -f "/usr/share/misc/magic.mgc" ]; then
        mkdir -p "$APPDIR/usr/share/misc"
        cp "/usr/share/misc/magic.mgc" "$APPDIR/usr/share/misc/" 2>/dev/null || true
    fi
fi
