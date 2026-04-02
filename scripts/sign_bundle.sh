#!/usr/bin/env bash
# sign_bundle.sh — strip xattrs and ad-hoc sign a .app bundle
# Usage: sign_bundle.sh /path/to/App.app
set -euo pipefail

BUNDLE="$1"

if [ ! -d "$BUNDLE" ]; then
    echo "ERROR: Bundle not found: $BUNDLE"
    exit 1
fi

# Strip ALL extended attributes (resource forks, FinderInfo, quarantine)
# that macdeployqt leaves behind — codesign rejects bundles with them.
xattr -cr "$BUNDLE"
find "$BUNDLE" -name '._*' -delete 2>/dev/null || true

# Ad-hoc sign. --deep re-signs nested frameworks and dylibs.
# For notarized distribution, replace `--sign -` with a Developer ID.
codesign --force --deep --sign - "$BUNDLE" 2>&1 || {
    echo "WARNING: ad-hoc signing failed (non-fatal for dev builds)"
    exit 0
}

echo "Signed: $BUNDLE"
