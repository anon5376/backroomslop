#!/bin/sh
# PLAY-BACKROOMS: double-click this file. It copies the game to your
# Desktop and launches it. A Terminal window will pop up; close it after.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ZIP="$HERE/build/backrooms-mac.zip"
APP="Backrooms- Signal Lost.app"
if [ ! -f "$ZIP" ]; then
    echo "Missing game archive: $ZIP"
    echo "Press Enter to close."
    read -r _
    exit 1
fi
echo "Installing to Desktop..."
unzip -o -q "$ZIP" -d "$HOME/Desktop/"
# Belt and braces: clear any quarantine flag so it opens directly.
xattr -dr com.apple.quarantine "$HOME/Desktop/$APP" 2>/dev/null || true
echo "Launching $APP ..."
open "$HOME/Desktop/$APP"
echo "Done. The game should be opening now - you can close this window."
