#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# grant_permission.sh — Permission management and dependency setup for Linux
# Ensures AT-SPI2 accessibility is enabled, checks X11/XTest, Tesseract OCR,
# and system audio player bindings.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "🔑 Managing Permissions & System Dependencies for NoInteraction (Linux)..."
echo ""

# 1. Check & Enable AT-SPI2 Accessibility in GNOME / KDE / XFCE
echo "1. Checking AT-SPI2 Desktop Accessibility..."
if command -v gsettings >/dev/null 2>&1; then
    CURRENT_AT_SPI=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || echo "false")
    if [ "$CURRENT_AT_SPI" != "true" ]; then
        echo "   Activating GTK/Electron AT-SPI accessibility via gsettings..."
        gsettings set org.gnome.desktop.interface toolkit-accessibility true || true
        echo "   ✓ Enabled toolkit-accessibility in GNOME interface settings."
    else
        echo "   ✓ AT-SPI toolkit-accessibility is already enabled."
    fi
else
    echo "   ⚠️ gsettings command not found. Ensure GTK_MODULES=gail:atk-bridge is set in your environment if AT-SPI is idle."
fi

echo ""
# 2. Check X11 / XTest / Wayland Session
echo "2. Checking Display Server & Synthetic Click Support..."
SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
echo "   Current Session Type: $SESSION_TYPE"
if [ "$SESSION_TYPE" = "wayland" ]; then
    echo "   ⚠️ Running under native Wayland. AT-SPI native actions will function,"
    echo "      but XTest cursor click fallbacks require XWayland."
else
    echo "   ✓ Running under X11 / XWayland session."
fi

echo ""
# 3. Check Tesseract OCR Binary
echo "3. Checking Tesseract OCR Binary..."
if command -v tesseract >/dev/null 2>&1; then
    TESS_VER=$(tesseract --version 2>&1 | head -n 1)
    echo "   ✓ Tesseract OCR installed ($TESS_VER)."
else
    echo "   ⚠️ Tesseract OCR binary not found in PATH."
    echo "      Install it using your package manager for vision fallback support:"
    echo "        Debian/Ubuntu: sudo apt install tesseract-ocr"
    echo "        Fedora:        sudo dnf install tesseract"
    echo "        Arch:          sudo pacman -S tesseract"
fi

echo ""
# 4. Check Audio Player
echo "4. Checking Audio Feedback System..."
if command -v paplay >/dev/null 2>&1 || command -v canberra-gtk-play >/dev/null 2>&1 || command -v aplay >/dev/null 2>&1; then
    echo "   ✓ Audio playback engine available."
else
    echo "   ⚠️ No standard audio player (paplay/canberra-gtk-play/aplay) found. Sound feedback will be silent."
fi

echo ""
# 5. Check Python System Bindings
echo "5. Checking Python pyatspi & gi bindings..."
python3 -c "import pyatspi, gi" 2>/dev/null && echo "   ✓ System pyatspi & gi bindings are working." || {
    echo "   ⚠️ Missing system pyatspi or gi bindings."
    echo "      Install them via: sudo apt install python3-pyatspi python3-gi gir1.2-atspi-2.0"
}

echo ""
echo "🚀 Permissions and setup check complete!"
