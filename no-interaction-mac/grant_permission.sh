#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# grant_permission.sh — Permanently grants macOS Accessibility permission to
# NoInteraction WITHOUT needing to open System Settings every time.
# Run once: bash grant_permission.sh
# ──────────────────────────────────────────────────────────────────────────────

BUNDLE_ID="com.antigravity.nointeraction"
INSTALL_PATH="/Applications/NoInteraction.app"
LOCAL_APP="$(cd "$(dirname "$0")" && pwd)/build_dist/NoInteraction.app"

echo "🔑 Managing Permissions for NoInteraction on macOS..."
echo ""

# Verify app exists in build_dist or /Applications
if [ -d "$LOCAL_APP" ]; then
    TARGET_APP="$LOCAL_APP"
elif [ -d "$INSTALL_PATH" ]; then
    TARGET_APP="$INSTALL_PATH"
else
    echo "⚠️ NoInteraction.app not found in build_dist/ or /Applications/. Running build.sh first..."
    bash "$(dirname "$0")/build.sh"
    TARGET_APP="$LOCAL_APP"
fi

echo "1. Checking Accessibility Permission (kTCCServiceAccessibility)..."
echo "   Opening macOS System Settings -> Privacy & Security -> Accessibility..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "2. Checking Automation Permission (kTCCServiceAppleEvents -> Terminal.app)..."
echo "   Opening macOS System Settings -> Privacy & Security -> Automation..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo ""
echo "📋 INSTRUCTIONS TO COMPLETE PERMISSION GRANT:"
echo "   a. Under Accessibility: Ensure 'NoInteraction' is enabled (ticked ✓)."
echo "   b. Under Automation: Ensure 'NoInteraction' has permission to control 'Terminal'."
echo ""
echo "🚀 Resetting TCC cache for $BUNDLE_ID (if previously denied)..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "🚀 Relaunching NoInteraction..."
pkill -x NoInteraction 2>/dev/null || true
sleep 0.5
open "$TARGET_APP"

echo "✅ Permission management script complete!"

