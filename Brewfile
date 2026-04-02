# Brewfile — macOS development dependencies for Anyfile
#
# Install everything at once:
#   brew bundle
#
# Check what's missing without installing:
#   brew bundle check
#
# Remove anything installed by this file that is no longer listed:
#   brew bundle cleanup

# ── Build tools ───────────────────────────────────────────────────────────────
brew "cmake"
brew "ninja"
brew "pkg-config"

# ── Core library dependencies ─────────────────────────────────────────────────
brew "ffmpeg"          # Media conversion (audio, video, images)
brew "assimp"          # 3D model conversion
brew "libarchive"      # Archive extraction and repacking
brew "libmagic"        # File type detection via magic bytes (optional but recommended)
brew "poppler"         # PDF rendering (pdftoppm)

# ── Document / ebook converters (optional — only needed for those formats) ────
brew "pandoc"          # Markdown, HTML, RST, and other document formats

# ── GUI ───────────────────────────────────────────────────────────────────────
brew "qt@6"            # Qt6 framework for the GUI frontend

# ── Packaging (only needed when building a distributable DMG) ────────────────
brew "create-dmg"      # Drag-to-install DMG packaging

# ── Optional: GUI apps installed as casks ─────────────────────────────────────
# Uncomment these if you need document/ebook conversion support.
# They are large downloads and are not required for core functionality.
# cask "libreoffice"   # Office document conversion (.docx, .odt, .pptx, etc.)
# cask "calibre"       # Ebook conversion (.epub, .mobi, .azw3, etc.)
