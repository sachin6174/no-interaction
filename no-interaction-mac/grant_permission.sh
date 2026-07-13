#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# grant_permission.sh — Permanently grants macOS Accessibility permission to
# NoInteraction WITHOUT needing to open System Settings every time.
# Run once: bash grant_permission.sh
# ──────────────────────────────────────────────────────────────────────────────

BUNDLE_ID="com.antigravity.nointeraction"
INSTALL_PATH="/Applications/NoInteraction.app"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

echo "🔑 Granting Accessibility permission to NoInteraction..."

# Verify app exists
if [ ! -d "$INSTALL_PATH" ]; then
    echo "❌ $INSTALL_PATH not found. Run build.sh first."
    exit 1
fi

# macOS 13+: Use sudo to write to the system TCC database
# This grants Accessibility permanently, surviving app updates as long as
# the bundle ID (com.antigravity.nointeraction) stays the same.
sudo sqlite3 "$TCC_DB" \
"INSERT OR REPLACE INTO access \
(service, client, client_type, auth_value, auth_reason, auth_version, \
 csreq, policy_id, indirect_object_identifier_type, \
 indirect_object_identifier, indirect_object_code_identity, flags, last_modified) \
VALUES \
('kTCCServiceAccessibility', '$BUNDLE_ID', 0, 2, 4, 1, \
 NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));" 2>&1

STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo "✅ Accessibility permission GRANTED permanently!"
    echo "   Bundle ID: $BUNDLE_ID"
    echo ""
    echo "🚀 Relaunching NoInteraction..."
    pkill -x NoInteraction 2>/dev/null || true
    sleep 0.5
    open "$INSTALL_PATH"
    echo "✅ Done! NoInteraction is now monitoring Anti-Gravity."
else
    echo ""
    echo "⚠️  TCC database write failed (SIP may be blocking it)."
    echo ""
    echo "Manual alternative — open this URL in Safari:"
    echo "   x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo ""
    echo "Then tick ✓ NoInteraction in the list."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi
