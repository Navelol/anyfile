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

# Sign individual dylibs and frameworks bottom-up first.
# --deep is unreliable — it doesn't guarantee correct signing order,
# which leaves nested libraries with invalid signatures.
find "$BUNDLE" -name '*.dylib' -print0 | xargs -0 -n1 codesign --force --sign - 2>&1 || true
find "$BUNDLE" -name '*.framework' -print0 | xargs -0 -n1 codesign --force --sign - 2>&1 || true

# Sign the top-level bundle last.
codesign --force --sign - "$BUNDLE" 2>&1 || {
    echo "WARNING: ad-hoc signing failed (non-fatal for dev builds)"
    exit 0
}

echo "Signed: $BUNDLE"
