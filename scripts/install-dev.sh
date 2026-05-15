#!/usr/bin/env bash
#
# install-dev.sh - build, bundle, and install Insomnia.app into /Applications
# for local testing.
#
# Usage: ./scripts/install-dev.sh [debug|release]   (default: debug)

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
./Bundle/bundle.sh "${CONFIG}"

echo "Installing to /Applications/Insomnia.app ..."
rm -rf /Applications/Insomnia.app
cp -R dist/Insomnia.app /Applications/Insomnia.app

echo "Installed. Launch with:  open /Applications/Insomnia.app"
