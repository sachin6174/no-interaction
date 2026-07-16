"""XTest-based synthetic click — the Linux/X11 equivalent of the Mac build's
CGEvent-based ClickAutomation. Restores the user's original cursor position
immediately after clicking so typing is never interrupted.

Requires an X11 (or XWayland) session; native Wayland has no equivalent of
XTest, so this fallback click path won't work there. AT-SPI action invocation
(the primary path in atspi_inspector.py) is unaffected either way.
"""

from __future__ import annotations

import threading
import time
from typing import Callable, Optional

from Xlib import X, display
from Xlib.ext import xtest


class ClickAutomation:
    _instance: Optional["ClickAutomation"] = None

    @classmethod
    def shared(cls) -> "ClickAutomation":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._disp = None
        self._wayland_warning_logged = False
        try:
            self._disp = display.Display()
        except Exception as e:
            print(f"[ClickAutomation] X11 Display connection failed (likely running native Wayland): {e}")

    def perform_click(self, point: tuple[int, int], completion: Optional[Callable[[], None]] = None) -> None:
        threading.Thread(target=self._click_worker, args=(point, completion), daemon=True).start()

    def _click_worker(self, point: tuple[int, int], completion: Optional[Callable[[], None]]) -> None:
        if self._disp is None:
            if not self._wayland_warning_logged:
                print("[ClickAutomation] WARNING: Fallback clicks are disabled. Native Wayland sessions do not support XTest. Please switch to X11/XWayland if synthetic click fallbacks are required.")
                self._wayland_warning_logged = True
            if completion:
                completion()
            return

        try:
            disp = self._disp
            root = disp.screen().root
            original = root.query_pointer()
            orig_x, orig_y = original.root_x, original.root_y

            x, y = int(point[0]), int(point[1])

            xtest.fake_input(disp, X.MotionNotify, x=x, y=y)
            disp.sync()
            time.sleep(0.01)
            xtest.fake_input(disp, X.ButtonPress, 1)
            disp.sync()
            time.sleep(0.03)
            xtest.fake_input(disp, X.ButtonRelease, 1)
            disp.sync()
            time.sleep(0.01)

            xtest.fake_input(disp, X.MotionNotify, x=orig_x, y=orig_y)
            disp.sync()

            print(f"[ClickAutomation] Clicked ({x}, {y}) and restored cursor to ({orig_x}, {orig_y})")
        except Exception as e:
            print(f"[ClickAutomation] Click failed: {e}")
        finally:
            if completion:
                completion()

    def press_paste_keystroke(self) -> None:
        if self._disp is None:
            return
        try:
            disp = self._disp
            # XK_Control_L keysym is 0xffe3
            # XK_v keysym is 0x0076
            ctrl_keycode = disp.keysym_to_keycode(0xffe3)
            v_keycode = disp.keysym_to_keycode(0x0076)
            
            xtest.fake_input(disp, X.KeyPress, ctrl_keycode)
            disp.sync()
            time.sleep(0.02)
            xtest.fake_input(disp, X.KeyPress, v_keycode)
            disp.sync()
            time.sleep(0.05)
            xtest.fake_input(disp, X.KeyRelease, v_keycode)
            disp.sync()
            time.sleep(0.02)
            xtest.fake_input(disp, X.KeyRelease, ctrl_keycode)
            disp.sync()
            print("[ClickAutomation] Simulated Ctrl+V press")
        except Exception as e:
            print(f"[ClickAutomation] Paste failed: {e}")

    def press_return_key(self) -> None:
        if self._disp is None:
            return
        try:
            disp = self._disp
            # XK_Return keysym is 0xff0d
            return_keycode = disp.keysym_to_keycode(0xff0d)
            
            xtest.fake_input(disp, X.KeyPress, return_keycode)
            disp.sync()
            time.sleep(0.05)
            xtest.fake_input(disp, X.KeyRelease, return_keycode)
            disp.sync()
            print("[ClickAutomation] Simulated Return press")
        except Exception as e:
            print(f"[ClickAutomation] Return press failed: {e}")

    def send_string(self, text: str) -> None:
        if self._disp is None:
            return
        try:
            disp = self._disp
            for char in text:
                if char == '\n':
                    keysym = 0xff0d  # XK_Return
                elif char == '\t':
                    keysym = 0xff09  # XK_Tab
                else:
                    keysym = ord(char)
                
                keycode = disp.keysym_to_keycode(keysym)
                if keycode == 0:
                    continue
                    
                xtest.fake_input(disp, X.KeyPress, keycode)
                disp.sync()
                time.sleep(0.01)
                xtest.fake_input(disp, X.KeyRelease, keycode)
                disp.sync()
                time.sleep(0.01)
            print(f"[ClickAutomation] Typed string: '{text.replace('\n', '\\n')}'")
        except Exception as e:
            print(f"[ClickAutomation] Send string failed: {e}")

