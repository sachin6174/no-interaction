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

DEFAULT_PROMPT = """Perform a complete, exhaustive, and uncompromising security, architecture, performance, and UI/UX audit of this entire codebase. Analyze every single line of code with extreme depth and rigor.

Your objective is to optimize this application to the absolute highest tier of software quality in existence. Follow these strict directives:
1. BUG DETECTION & RESOLUTION: Scan for any logical bugs, concurrency race conditions, memory leaks, performance bottlenecks, edge-case crashes, and API misuses. Resolve them immediately with clean, production-ready, and robust code.
2. CODE OPTIMIZATION & REFACTORING: Optimize compile times, memory footprints, and CPU utilization. Eliminate redundant loops, redundant accessibility calls, and heavy UI renderings. Ensure optimal Swift concurrency paradigms.
3. UI/UX REFINEMENT: Review all layouts, fonts, spacing, color contrasts, transitions, and hover animations. Upgrade the visual design system to feel premium, modern, and state-of-the-art.
4. EDGE CASES & ROBUSTNESS: Ensure perfect error handling, validation, and defensive coding against unexpected window hierarchies, missing permissions, or browser states.
5. DEEP SEARCH: Use the internet, latest documentation, Apple SDK guidelines, and the full extent of your cognitive capacity. Do not stop until this codebase is completely flawless."""


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
        self.prompt_queue: list[str] = [DEFAULT_PROMPT]
        self.current_prompt_index: int = 0
        self.is_prompt_queue_active: bool = True
        self.loop_mode_enabled: bool = False
        self.loop_mode_limit: int = 10
        self.loop_mode_counter: int = 0

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
                if "promptQueue" in data:
                    store.prompt_queue = data["promptQueue"]
                store.current_prompt_index = data.get("currentPromptIndex", 0)
                store.is_prompt_queue_active = data.get("isPromptQueueActive", True)
                store.loop_mode_enabled = data.get("loopModeEnabled", False)
                store.loop_mode_limit = data.get("loopModeLimit", 10)
                store.loop_mode_counter = data.get("loopModeCounter", 0)
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
                "promptQueue": self.prompt_queue,
                "currentPromptIndex": self.current_prompt_index,
                "isPromptQueueActive": self.is_prompt_queue_active,
                "loopModeEnabled": self.loop_mode_enabled,
                "loopModeLimit": self.loop_mode_limit,
                "loopModeCounter": self.loop_mode_counter,
            }
            SETTINGS_PATH.write_text(json.dumps(data, indent=2))
        except Exception:
            # Best-effort persistence; a failed save should never crash the scan loop.
            pass
