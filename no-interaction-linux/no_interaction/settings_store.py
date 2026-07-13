"""JSON-file settings persistence at ~/.config/no-interaction/settings.json —
the Linux equivalent of the Mac build's UserDefaults-backed storage."""

from __future__ import annotations

import json
import os
from pathlib import Path

from .models import ApprovalRule, TargetType

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "no-interaction"
SETTINGS_PATH = CONFIG_DIR / "settings.json"

DEFAULT_BUTTONS = [
    "Submit", "Allow", "Yes, allow", "Yes, and always", "Approve",
    "Yes", "Confirm", "Proceed", "Accept", "Continue", "OK",
]
DEFAULT_CHECKBOXES = ["Remember", "Always", "Trust", "Don't ask", "Don't show"]


class SettingsStore:
    def __init__(self):
        self.is_enabled: bool = True
        self.sound_enabled: bool = True
        self.total_approvals_count: int = 0
        self.button_rules: list[ApprovalRule] = [
            ApprovalRule(k, TargetType.BUTTON) for k in DEFAULT_BUTTONS
        ]
        self.checkbox_rules: list[ApprovalRule] = [
            ApprovalRule(k, TargetType.CHECKBOX) for k in DEFAULT_CHECKBOXES
        ]

    @staticmethod
    def load() -> "SettingsStore":
        store = SettingsStore()
        try:
            if SETTINGS_PATH.exists():
                data = json.loads(SETTINGS_PATH.read_text())
                store.is_enabled = data.get("isEnabled", True)
                store.sound_enabled = data.get("soundEnabled", True)
                store.total_approvals_count = data.get("totalApprovalsCount", 0)
                if data.get("buttonRules"):
                    store.button_rules = [ApprovalRule.from_dict(r) for r in data["buttonRules"]]
                if data.get("checkboxRules"):
                    store.checkbox_rules = [ApprovalRule.from_dict(r) for r in data["checkboxRules"]]
        except Exception:
            # Corrupt or unreadable settings file — fall back to defaults.
            pass

        # Sanitize: remove Run/Execute to prevent conflict with IDE "Run Code" buttons.
        store.button_rules = [
            r for r in store.button_rules
            if r.keyword.lower() not in ("run", "execute")
        ]
        return store

    def save(self) -> None:
        try:
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            data = {
                "isEnabled": self.is_enabled,
                "soundEnabled": self.sound_enabled,
                "totalApprovalsCount": self.total_approvals_count,
                "buttonRules": [r.to_dict() for r in self.button_rules],
                "checkboxRules": [r.to_dict() for r in self.checkbox_rules],
            }
            SETTINGS_PATH.write_text(json.dumps(data, indent=2))
        except Exception:
            # Best-effort persistence; a failed save should never crash the scan loop.
            pass
