#!/usr/bin/env bash
#
# bundle.sh - assemble dist/Insomnia.app from the SwiftPM build products.
#
# Usage: ./Bundle/bundle.sh [debug|release]   (default: release)
#
# SwiftPM can't emit a .app bundle, but a menu bar app is just a directory with
# an Info.plist and the two executables. This script builds them, lays out the
# bundle, and ad-hoc signs it.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="dist/Insomnia.app"

echo "Building Insomnia + insomnia-hook (${CONFIG})..."
swift build -c "${CONFIG}" --product Insomnia      >/dev/null
swift build -c "${CONFIG}" --product insomnia-hook >/dev/null
BIN="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp Bundle/Info.plist    "${APP}/Contents/Info.plist"
cp Bundle/AppIcon.icns  "${APP}/Contents/Resources/AppIcon.icns"
cp "${BIN}/Insomnia"      "${APP}/Contents/MacOS/Insomnia"
cp "${BIN}/insomnia-hook" "${APP}/Contents/MacOS/insomnia-hook"

# Ad-hoc signature: free, needs no Apple Developer account. It gives the bundle
# a stable code identity (so SMAppService login-item registration survives
# rebuilds). This is NOT notarization - first launch still needs the Gatekeeper
# right-click -> Open step (see docs/GATEKEEPER.md).
echo "Ad-hoc signing..."
codesign --force --deep --sign - "${APP}"

echo "Done -> ${APP}"
