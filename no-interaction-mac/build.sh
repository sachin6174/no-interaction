#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# build.sh — NoInteraction macOS App Build, Signing, Notarization & Installer
# ──────────────────────────────────────────────────────────────────────────────
set -e

echo "🔨 Building NoInteraction macOS App..."

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build_dist"
APP_BUNDLE="$BUILD_DIR/NoInteraction.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
INSTALL_PATH="/Applications/NoInteraction.app"
ZIP_PATH="$BUILD_DIR/NoInteraction.zip"
DMG_PATH="$BUILD_DIR/NoInteraction-v1.2.0.dmg"
PKG_PATH="$BUILD_DIR/NoInteraction-v1.2.0.pkg"

# Apple Credentials & Credentials Profile
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-"AC_PASSWORD"}"
APPLE_ID="${APPLE_ID:-"letslearngpt@gmail.com"}"
TEAM_ID="${TEAM_ID:-"M5Q7N9D29M"}"

ENTITLEMENTS_PATH="$PROJECT_DIR/NoInteraction/Resources/NoInteraction.entitlements"
INFO_PLIST_PATH="$PROJECT_DIR/NoInteraction/Resources/Info.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📦 Compiling via Swift Package Manager..."
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/NoInteraction"
if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed: binary not found"
    exit 1
fi

cp "$BINARY" "$MACOS_DIR/NoInteraction"
cp "$INFO_PLIST_PATH" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PROJECT_DIR/NoInteraction/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/NoInteraction/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# ── Code Sign with Developer ID Application Identity ──────────────────────────
echo "🔏 Searching for Developer ID Application Certificate..."
FOUND_CERT=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || true)

if [ -n "$FOUND_CERT" ]; then
    echo "  ✓ Found Certificate: $FOUND_CERT"
    codesign --force --deep --options runtime \
             --timestamp \
             --entitlements "$ENTITLEMENTS_PATH" \
             --sign "$FOUND_CERT" \
             "$APP_BUNDLE"
    echo "✅ Signed App with Hardened Runtime."
else
    echo "⚠️  No Developer ID Certificate found, fallback to ad-hoc signing..."
    codesign --force --deep --sign - "$APP_BUNDLE" || true
fi

# ── Notarize with Apple Notary Service ─────────────────────────────────────────
NOTARIZE_SUCCESS=false
if [ "$SKIP_NOTARIZATION" = "true" ]; then
    echo "☁️  Skipping Notarization for fast local development build..."
else
    echo "☁️  Submitting NoInteraction to Apple Notary Service..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    if xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait; then
        echo "✅ Notarization Successful!"
        NOTARIZE_SUCCESS=true
    fi

    if [ "$NOTARIZE_SUCCESS" = true ]; then
        echo "🏷️  Stapling Notarization ticket to App Bundle..."
        xcrun stapler staple "$APP_BUNDLE" || true
    fi
fi

# ── Create Official macOS .pkg & .dmg Installer Packages ─────────────────────
echo "📦 Generating macOS .pkg & .dmg Installer Packages..."
pkgbuild --root "$APP_BUNDLE" \
         --install-location "$INSTALL_PATH" \
         --identifier "com.antigravity.nointeraction" \
         --version "1.2.0" \
         "$PKG_PATH" 2>&1

hdiutil create -volname "NoInteraction Installer" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

# ── Install to /Applications ──────────────────────────────────────────────────
echo "📲 Installing to /Applications..."
pkill -x NoInteraction 2>/dev/null || true
sleep 0.5

rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "✅ Installed: $INSTALL_PATH"

# ── Relaunch App ──────────────────────────────────────────────────────────────
open "$INSTALL_PATH"
echo ""
echo "🚀 NoInteraction v1.2 successfully built, signed & launched!"
echo "📦 .pkg Installer available at: $PKG_PATH"
