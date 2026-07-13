"""Finds target applications (Antigravity / VS Code / browsers) via the AT-SPI
accessibility registry — the Linux equivalent of the Mac build's AppObserver.

Note: the target application must expose an AT-SPI accessible tree. GTK apps do
this automatically; Electron/Chromium apps (VS Code, Antigravity, browsers)
enable their accessibility bridge once an AT-SPI client is detected on the
session bus, which can take a moment (or a restart of the target app) after
NoInteraction first starts.
"""

from __future__ import annotations

from typing import Optional

import pyatspi

TARGET_APP_NAMES = [
    "Antigravity", "Anti-Gravity", "AntiGravity",
    "Visual Studio Code", "VS Code", "VSCode", "Code",
]
EDITOR_NAMES = ["visual studio code", "vs code", "vscode", "cursor", "windsurf", "antigravity", "code"]
BROWSER_NAMES = ["chrome", "chromium", "firefox", "brave", "opera", "vivaldi", "edge"]
ANTIGRAVITY_WINDOW_KEYWORDS = ["antigravity", "anti-gravity", "agy", "gemini", "no-interaction"]


class AppObserver:
    _instance: Optional["AppObserver"] = None

    @classmethod
    def shared(cls) -> "AppObserver":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def _desktop(self):
        return pyatspi.Registry.getDesktop(0)

    def find_target_applications(self, custom_targets: Optional[list[str]] = None):
        targets = [t for t in (TARGET_APP_NAMES + (custom_targets or [])) if t]
        results = []
        desktop = self._desktop()
        for i in range(desktop.childCount):
            try:
                app = desktop.getChildAtIndex(i)
            except Exception:
                continue
            name = (getattr(app, "name", "") or "")
            if any(t.lower() in name.lower() for t in targets):
                results.append(app)
        return results

    def is_browser(self, app) -> bool:
        name = (getattr(app, "name", "") or "").lower()
        return any(b in name for b in BROWSER_NAMES)

    def is_editor(self, app) -> bool:
        name = (getattr(app, "name", "") or "").lower()
        return any(e in name for e in EDITOR_NAMES)

    def is_browser_or_editor(self, app) -> bool:
        return self.is_browser(app) or self.is_editor(app)

    def is_antigravity_window(self, window) -> bool:
        try:
            title = (window.name or "").lower()
        except Exception:
            return False
        return any(k in title for k in ANTIGRAVITY_WINDOW_KEYWORDS)

    def top_level_windows(self, app) -> list:
        windows = []
        try:
            for i in range(app.childCount):
                try:
                    windows.append(app.getChildAtIndex(i))
                except Exception:
                    continue
        except Exception:
            pass
        return windows

    def get_window_bounds(self, app) -> Optional[tuple[int, int, int, int]]:
        """Returns (x, y, width, height) in screen pixels for the largest relevant window."""
        windows = self.top_level_windows(app)
        if not windows:
            return None

        candidates = windows
        if self.is_browser(app):
            filtered = [w for w in windows if self.is_antigravity_window(w)]
            if filtered:
                candidates = filtered

        best = None
        best_area = 0
        for win in candidates:
            rect = self.extents(win)
            if rect is None:
                continue
            _, _, w, h = rect
            if w <= 50 or h <= 50:
                continue
            area = w * h
            if area > best_area:
                best_area = area
                best = rect
        return best

    def extents(self, element) -> Optional[tuple[int, int, int, int]]:
        try:
            component = element.queryComponent()
            ext = component.getExtents(pyatspi.XY_SCREEN)
            return (ext.x, ext.y, ext.width, ext.height)
        except Exception:
            return None
