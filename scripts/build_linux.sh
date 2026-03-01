#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build/linux"

# ── Parse flags ──────────────────────────────────────────────────────────────
BUILD_GUI=OFF
BUILD_TYPE=Release

for arg in "$@"; do
    case "$arg" in
        --gui)        BUILD_GUI=ON ;;
        --debug)      BUILD_TYPE=Debug ;;
        --release)    BUILD_TYPE=Release ;;
    esac
done

echo ""
echo "┌─ Build Config ───────────────────────────────┐"
echo "│  Type : $BUILD_TYPE"
echo "│  GUI  : $BUILD_GUI"
echo "└──────────────────────────────────────────────┘"
echo ""

# ── Configure ────────────────────────────────────────────────────────────────
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_GUI="$BUILD_GUI"

# ── Build ────────────────────────────────────────────────────────────────────
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

echo ""
echo "Build complete → $BUILD_DIR/bin/"
