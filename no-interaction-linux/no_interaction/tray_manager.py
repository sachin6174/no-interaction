"""System tray equivalent of the Mac build's MenuBarManager, built on pystray.

Note: most Linux tray backends (AppIndicator/Ayatana) don't distinguish a
left-click from a right-click the way macOS/Windows do — clicking the icon
always opens the menu. Use "Open Dashboard..." from that menu.
"""

from __future__ import annotations

from typing import Callable, Optional

import pystray
from PIL import Image, ImageDraw

from .approver_engine import ApproverEngine


def _make_icon_image(color: str) -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((8, 8, 56, 56), fill=color)
    return img


class TrayManager:
    _instance: Optional["TrayManager"] = None

    @classmethod
    def shared(cls) -> "TrayManager":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._icon: Optional[pystray.Icon] = None
        self._show_dashboard_callback: Optional[Callable[[], None]] = None
        self._quit_callback: Optional[Callable[[], None]] = None

    def set_show_dashboard_callback(self, callback: Callable[[], None]) -> None:
        self._show_dashboard_callback = callback

    def set_quit_callback(self, callback: Callable[[], None]) -> None:
        self._quit_callback = callback

    def setup(self) -> None:
        engine = ApproverEngine.shared()
        self._icon = pystray.Icon("no-interaction", self._current_image(), "NoInteraction", menu=self._build_menu())
        engine.add_listener(self._refresh)
        self._icon.run_detached()

    def _current_image(self) -> Image.Image:
        engine = ApproverEngine.shared()
        return _make_icon_image("#2ecc71" if engine.is_enabled else "#95a5a6")

    def _build_menu(self) -> pystray.Menu:
        engine = ApproverEngine.shared()
        status = "Active" if engine.is_enabled else "Paused"
        return pystray.Menu(
            pystray.MenuItem(f"{status} — {engine.total_approvals_count} Approved", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Pause Monitoring" if engine.is_enabled else "Resume Monitoring", self._toggle_enabled),
            pystray.MenuItem("Mute Sound Feedback" if engine.sound_enabled else "Enable Sound Feedback", self._toggle_sound),
            pystray.MenuItem("Open Dashboard...", self._open_dashboard, default=True),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit NoInteraction", self._quit),
        )

    def _refresh(self) -> None:
        if self._icon is None:
            return
        self._icon.icon = self._current_image()
        self._icon.menu = self._build_menu()

    def _toggle_enabled(self, icon, item) -> None:
        engine = ApproverEngine.shared()
        engine.is_enabled = not engine.is_enabled

    def _toggle_sound(self, icon, item) -> None:
        engine = ApproverEngine.shared()
        engine.sound_enabled = not engine.sound_enabled

    def _open_dashboard(self, icon, item) -> None:
        if self._show_dashboard_callback:
            self._show_dashboard_callback()

    def _quit(self, icon, item) -> None:
        ApproverEngine.shared().stop()
        icon.stop()
        if self._quit_callback:
            self._quit_callback()

    def shutdown(self) -> None:
        if self._icon:
            self._icon.stop()
