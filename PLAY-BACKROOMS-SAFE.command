#!/bin/sh
# BACKROOMS SAFE MODE: double-click this if the normal app hangs on launch.
# Forces the Compatibility (OpenGL) renderer instead of Forward+/Metal.
set -u
APP="$HOME/Desktop/Backrooms- Signal Lost.app"
if [ ! -d "$APP" ]; then
    echo "Not found: $APP"
    echo "Run PLAY-BACKROOMS.command first (or unzip build/backrooms-mac.zip to Desktop)."
    echo "Press Enter to close."
    read -r _
    exit 1
fi
echo "Launching in Compatibility mode..."
open "$APP" --args --rendering-method gl_compatibility --rendering-driver opengl3
echo "Launched. You can close this window."
