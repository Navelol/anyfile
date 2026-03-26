#!/usr/bin/env bash
# ── build_macos.sh ────────────────────────────────────────────────────────────
# Builds Anyfile on macOS, optionally packaging it as a distributable DMG.
#
# Usage:
#   ./scripts/build_macos.sh [options]
#
# Options:
#   --gui        Build the Qt6 GUI in addition to the CLI
#   --dmg        Package the GUI .app bundle into a distributable DMG
#                (implies --gui)
#   --no-tests   Skip the unit test suite
#   --debug      Debug build (default: Release)
#   --release    Release build (default)
#
# Prerequisites:
#   All dependencies are listed in the Brewfile at the project root.
#   Install everything in one command:
#     brew bundle
#   This script runs `brew bundle check` automatically before building and
#   will tell you exactly what to install if anything is missing.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build/macos"

# ── Colour helpers (gracefully disabled when not connected to a terminal) ─────
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ ok ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
fail()    { echo -e "${RED}[fail]${RESET}  $*"; }
section() { echo -e "\n${BOLD}── $* ${RESET}"; }

# ── Parse flags ───────────────────────────────────────────────────────────────
BUILD_GUI=OFF
BUILD_TESTS=ON
BUILD_TYPE=Release
BUILD_DMG=OFF

for arg in "$@"; do
    case "$arg" in
        --gui)      BUILD_GUI=ON ;;
        --dmg)      BUILD_DMG=ON; BUILD_GUI=ON ;;
        --no-tests) BUILD_TESTS=OFF ;;
        --tests)    BUILD_TESTS=ON ;;
        --debug)    BUILD_TYPE=Debug ;;
        --release)  BUILD_TYPE=Release ;;
        *)          warn "Unknown flag: $arg (ignored)" ;;
    esac
done

# ── Detect Homebrew prefix (Apple Silicon vs Intel) ───────────────────────────
# We resolve the prefix at script runtime so the same script works on both
# architectures without hard-coding either path.
if command -v brew &>/dev/null; then
    BREW_PREFIX="$(brew --prefix)"
else
    fail "Homebrew is not installed."
    echo    "  Install it from https://brew.sh, then re-run this script."
    exit 1
fi

# ── Prerequisite check via Brewfile ──────────────────────────────────────────
# `brew bundle check` reads the Brewfile at the project root and verifies that
# every listed formula is installed.  If anything is missing it exits non-zero
# and we print a single actionable command — no raw CMake errors, ever.
section "Checking prerequisites"

if ! brew bundle check --file="$ROOT_DIR/Brewfile" 2>/dev/null; then
    echo ""
    warn "Some dependencies from the Brewfile are not installed."
    echo ""
    echo -e "  Run: ${BOLD}brew bundle --file=$ROOT_DIR/Brewfile${RESET}"
    echo ""
    echo    "  Or to install and immediately continue:"
    echo -e "  ${BOLD}brew bundle --file=$ROOT_DIR/Brewfile && $0 $*${RESET}"
    echo ""
    exit 1
fi

ok "All Brewfile dependencies satisfied"

# ── Generate app.icns from app.png (if not already present) ───────────────────
# CMake embeds app.icns into the .app bundle.  We generate it here from the
# existing app.png so the build stays hermetic without committing a binary blob.
ICNS_SRC="$ROOT_DIR/src/gui/resources/icons/app.png"
ICNS_OUT="$ROOT_DIR/src/gui/resources/icons/app.icns"

if [ ! -f "$ICNS_OUT" ]; then
    section "Generating app.icns"
    if [ ! -f "$ICNS_SRC" ]; then
        warn "app.png not found at $ICNS_SRC — skipping .icns generation."
        warn "The app bundle will launch without a custom dock icon."
    else
        ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
        mkdir -p "$ICONSET_DIR"

        # Generate all required icon sizes from the source PNG.
        # macOS iconsets require specific sizes; sips handles the resampling.
        for size in 16 32 64 128 256 512; do
            sips -z $size $size "$ICNS_SRC" \
                --out "$ICONSET_DIR/icon_${size}x${size}.png"       &>/dev/null
            sips -z $((size*2)) $((size*2)) "$ICNS_SRC" \
                --out "$ICONSET_DIR/icon_${size}x${size}@2x.png"    &>/dev/null
        done

        iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"
        ok "Generated $ICNS_OUT"
    fi
else
    ok "app.icns already exists — skipping generation"
fi

# ── Configure ─────────────────────────────────────────────────────────────────
section "Configuring (CMake)"

echo ""
echo -e "${BOLD}┌─ Build Config ────────────────────────────────┐${RESET}"
echo    "│  Type   : $BUILD_TYPE"
echo    "│  GUI    : $BUILD_GUI"
echo    "│  Tests  : $BUILD_TESTS"
echo    "│  DMG    : $BUILD_DMG"
echo -e "${BOLD}└───────────────────────────────────────────────┘${RESET}"
echo ""

# Pass the Homebrew prefix explicitly so CMake finds Qt6 even when the
# developer has not exported CMAKE_PREFIX_PATH in their shell profile.
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_GUI="$BUILD_GUI" \
    -DBUILD_TESTS="$BUILD_TESTS" \
    -DCMAKE_PREFIX_PATH="$BREW_PREFIX"

# ── Build ─────────────────────────────────────────────────────────────────────
section "Building"

cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.logicalcpu)"

ok "Build complete → $BUILD_DIR/bin/"

# ── Tests ─────────────────────────────────────────────────────────────────────
if [ "$BUILD_TESTS" = "ON" ]; then
    section "Running tests"
    ctest --test-dir "$BUILD_DIR" --output-on-failure
    ok "All tests passed"
fi

# ── DMG packaging ─────────────────────────────────────────────────────────────
# Produces a drag-to-install DMG: a window with the .app on the left and an
# alias to /Applications on the right, matching standard macOS installer UX.
if [ "$BUILD_DMG" = "ON" ]; then
    section "Packaging DMG"

    APP_BUNDLE="$BUILD_DIR/bin/anyfile_gui.app"
    DMG_STAGING="$BUILD_DIR/dmg_staging"
    DMG_OUT="$BUILD_DIR/Anyfile.dmg"

    if [ ! -d "$APP_BUNDLE" ]; then
        fail "App bundle not found at $APP_BUNDLE"
        fail "Make sure the GUI built successfully before packaging."
        exit 1
    fi

    # Clean any previous staging directory.
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"

    # copy the bundle into staging so create-dmg picks it up.
    cp -R "$APP_BUNDLE" "$DMG_STAGING/Anyfile.app"

    create-dmg \
        --volname "Anyfile" \
        --volicon "$ICNS_OUT" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "Anyfile.app" 165 185 \
        --hide-extension "Anyfile.app" \
        --app-drop-link 495 185 \
        "$DMG_OUT" \
        "$DMG_STAGING"

    # Generate a SHA-256 checksum alongside the DMG for release verification.
    shasum -a 256 "$DMG_OUT" > "${DMG_OUT}.sha256"

    ok "DMG → $DMG_OUT"
    ok "SHA → ${DMG_OUT}.sha256"
fi
