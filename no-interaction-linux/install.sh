#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# install.sh — One-click installer for NoInteraction on Linux
# - Installs system dependencies and virtual environment
# - Grants permissions (AT-SPI2, Tesseract, X11/XTest)
# - Installs Desktop shortcut (~/.local/share/applications/no-interaction.desktop)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "📦 Installing NoInteraction for Linux..."
echo ""

# 1. Make executable
chmod +x run.sh grant_permission.sh

# 2. Grant permissions & verify system dependencies
bash ./grant_permission.sh

# 3. Create virtual environment & install python dependencies
echo "🐍 Setting up Python virtual environment..."
if [ ! -d ".venv" ]; then
  python3 -m venv --system-site-packages .venv
fi
source .venv/bin/activate
pip install -q -r requirements.txt

# 4. Install Desktop Shortcut
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

cat <<EOF > "$DESKTOP_DIR/no-interaction.desktop"
[Desktop Entry]
Name=NoInteraction
Comment=Multi-Platform Anti-Gravity Prompt Approver
Exec=$DIR/run.sh
Icon=$DIR/app.ico
Terminal=false
Type=Application
Categories=Utility;Development;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/no-interaction.desktop"
echo "✓ Installed desktop shortcut at $DESKTOP_DIR/no-interaction.desktop"

echo ""
echo "🎉 Installation Complete! Launching NoInteraction..."
bash ./run.sh &
