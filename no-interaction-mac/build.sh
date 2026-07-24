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
DMG_PATH="$BUILD_DIR/NoInteraction-v1.3.0.dmg"
PKG_PATH="$BUILD_DIR/NoInteraction-v1.3.0.pkg"

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
    echo "  ✓ Found App Certificate: $FOUND_CERT"
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

# ── Create Official macOS .pkg & .dmg Installer Packages ─────────────────────
echo "📦 Generating macOS .pkg & .dmg Installer Packages..."

echo "🔏 Searching for Developer ID Installer Certificate..."
FOUND_INSTALLER_CERT=$(security find-identity -v | grep "Developer ID Installer" | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || true)

if [ -n "$FOUND_INSTALLER_CERT" ]; then
    echo "  ✓ Found Installer Certificate: $FOUND_INSTALLER_CERT"
    pkgbuild --component "$APP_BUNDLE" \
             --install-location "/Applications" \
             --identifier "com.antigravity.nointeraction" \
             --version "1.3.0" \
             --sign "$FOUND_INSTALLER_CERT" \
             "$PKG_PATH" 2>&1
    echo "✅ Signed .pkg Installer."
else
    echo "⚠️  No Developer ID Installer Certificate found, fallback to unsigned .pkg..."
    pkgbuild --component "$APP_BUNDLE" \
             --install-location "/Applications" \
             --identifier "com.antigravity.nointeraction" \
             --version "1.3.0" \
             "$PKG_PATH" 2>&1
fi

hdiutil create -volname "NoInteraction Installer" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

if [ -n "$FOUND_CERT" ]; then
    echo "🔏 Signing DMG..."
    codesign --force --sign "$FOUND_CERT" "$DMG_PATH"
    echo "✅ Signed .dmg Installer."
fi

# ── Notarize with Apple Notary Service ─────────────────────────────────────────
if [ "$SKIP_NOTARIZATION" = "true" ]; then
    echo "☁️  Skipping Notarization for fast local development build..."
else
    echo "☁️  Submitting Installer Packages to Apple Notary Service..."
    
    # Notarize PKG
    if [ -f "$PKG_PATH" ]; then
        echo "☁️  Submitting PKG installer: $PKG_PATH"
        if xcrun notarytool submit "$PKG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait; then
            echo "✅ PKG Notarization Successful!"
            echo "🏷️  Stapling Notarization ticket to PKG..."
            xcrun stapler staple "$PKG_PATH" || true
        else
            echo "❌ PKG Notarization Failed"
            exit 1
        fi
    fi

    # Notarize DMG
    if [ -f "$DMG_PATH" ]; then
        echo "☁️  Submitting DMG installer: $DMG_PATH"
        if xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait; then
            echo "✅ DMG Notarization Successful!"
            echo "🏷️  Stapling Notarization ticket to DMG..."
            xcrun stapler staple "$DMG_PATH" || true
        else
            echo "❌ DMG Notarization Failed"
            exit 1
        fi
    fi
    
    # Also staple the App Bundle itself
    echo "🏷️  Stapling Notarization ticket to App Bundle..."
    xcrun stapler staple "$APP_BUNDLE" || true
fi

# ── Install to /Applications ──────────────────────────────────────────────────
echo "📲 Installing to /Applications..."
pkill -x NoInteraction 2>/dev/null || true
sleep 0.5

if [ -d "$INSTALL_PATH" ]; then
    echo "🔑 Requesting sudo permission to remove previous installation..."
    sudo rm -rf "$INSTALL_PATH"
fi
sudo cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "✅ Installed: $INSTALL_PATH"

# ── Relaunch App ──────────────────────────────────────────────────────────────
open "$INSTALL_PATH"
echo ""
echo "🚀 NoInteraction v1.2 successfully built, signed & launched!"
echo "📦 .pkg Installer available at: $PKG_PATH"
echo "📦 .dmg Installer available at: $DMG_PATH"
