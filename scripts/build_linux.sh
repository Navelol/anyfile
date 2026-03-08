#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build/linux"

# ── Parse flags ──────────────────────────────────────────────────────────────
BUILD_GUI=OFF
BUILD_TESTS=ON
BUILD_TYPE=Release
BUILD_APPIMAGE=OFF

for arg in "$@"; do
    case "$arg" in
        --gui)        BUILD_GUI=ON   ;;
        --no-tests)   BUILD_TESTS=OFF ;;
        --tests)      BUILD_TESTS=ON  ;;
        --debug)      BUILD_TYPE=Debug   ;;
        --release)    BUILD_TYPE=Release ;;
        --appimage)   BUILD_APPIMAGE=ON; BUILD_GUI=ON ;;
    esac
done

echo ""
echo "┌─ Build Config ───────────────────────────────┐"
echo "│  Type  : $BUILD_TYPE"
echo "│  GUI   : $BUILD_GUI"
echo "│  Tests : $BUILD_TESTS"
echo "└──────────────────────────────────────────────┘"
echo ""

# ── Configure ────────────────────────────────────────────────────────────────
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_GUI="$BUILD_GUI" \
    -DBUILD_TESTS="$BUILD_TESTS"

# ── Build ────────────────────────────────────────────────────────────────────
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

echo ""
echo "Build complete → $BUILD_DIR/bin/"

if [ "$BUILD_APPIMAGE" = "ON" ]; then
    echo ""
    exec "$SCRIPT_DIR/build_appimage.sh" "$@"
fi
