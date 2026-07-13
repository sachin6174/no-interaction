#!/bin/bash
# Quick launcher for NoInteraction.app
APP="$(cd "$(dirname "$0")" && pwd)/build/NoInteraction.app"

if [ ! -d "$APP" ]; then
    echo "⚠️  App not built yet. Run ./build.sh first."
    exit 1
fi

echo "🚀 Launching NoInteraction..."
open "$APP"
