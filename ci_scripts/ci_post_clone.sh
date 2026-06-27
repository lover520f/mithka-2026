#!/bin/sh
set -e

# Xcode Cloud discovers custom scripts from the repository root. Keep the real
# Flutter/iOS setup script under ios/ so it can still be run from the Xcode
# project context, but make root discovery unambiguous.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../ios/ci_scripts/ci_post_clone.sh"
