#!/bin/bash
# Quick launcher for NoInteraction.app
APP_DIST="$(cd "$(dirname "$0")" && pwd)/build_dist/NoInteraction.app"
APP_INSTALLED="/Applications/NoInteraction.app"
APP_BUILD="$(cd "$(dirname "$0")" && pwd)/build/NoInteraction.app"

if [ -d "$APP_DIST" ]; then
    APP="$APP_DIST"
elif [ -d "$APP_INSTALLED" ]; then
    APP="$APP_INSTALLED"
elif [ -d "$APP_BUILD" ]; then
    APP="$APP_BUILD"
else
    echo "⚠️  App not built yet. Run ./build.sh first."
    exit 1
fi

echo "🚀 Launching NoInteraction from $APP..."
open "$APP"

