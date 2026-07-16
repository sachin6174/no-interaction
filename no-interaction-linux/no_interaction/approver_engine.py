"""Linux port of the Mac build's ApproverEngine: owns settings, rules, the
activity log, and the periodic scan loop. Intentionally does not include the
Mac app's Prompt Queue / Loop Mode auto-paste feature."""

from __future__ import annotations

import subprocess
import threading
import time
from typing import Callable, Optional

from .app_observer import AppObserver
from .atspi_inspector import AtspiInspector
from .click_automation import ClickAutomation
from .models import ApprovalRule, LogEntry, TargetType
from .ocr_scanner import OcrScanner
from .settings_store import DEFAULT_BUTTONS, DEFAULT_CHECKBOXES, SettingsStore, DEFAULT_PROMPT

SCAN_INTERVAL_SECONDS = 3.0
COOLDOWN_SECONDS = 1.2
MAX_LOG_ENTRIES = 200

SOUND_CANDIDATES = [
    "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
    "/usr/share/sounds/freedesktop/stereo/dialog-information.oga",
]


class ApproverEngine:
    _instance: Optional["ApproverEngine"] = None
    default_prompt = DEFAULT_PROMPT

    @classmethod
    def shared(cls) -> "ApproverEngine":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._settings = SettingsStore.load()

        self._is_enabled = self._settings.is_enabled
        self._sound_enabled = self._settings.sound_enabled
        self._total_approvals_count = self._settings.total_approvals_count

        self.button_rules: list[ApprovalRule] = list(self._settings.button_rules)
        self.checkbox_rules: list[ApprovalRule] = list(self._settings.checkbox_rules)
        self.logs: list[LogEntry] = []

        self._prompt_queue = self._settings.prompt_queue
        self._current_prompt_index = self._settings.current_prompt_index
        self._is_prompt_queue_active = self._settings.is_prompt_queue_active
        self._loop_mode_enabled = self._settings.loop_mode_enabled
        self._loop_mode_limit = self._settings.loop_mode_limit
        self._loop_mode_counter = self._settings.loop_mode_counter
        self._clipboard_callback: Optional[Callable[[str], None]] = None

        self._rules_lock = threading.Lock()
        self._logs_lock = threading.Lock()
        self._last_action_time = 0.0
        self._ocr_scan_in_flight = False
        self._scan_interval = SCAN_INTERVAL_SECONDS

        self._listeners: list[Callable[[], None]] = []
        self._stop_event = threading.Event()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

    # MARK: Listener registration (used by tray + dashboard to refresh UI)

    def add_listener(self, callback: Callable[[], None]) -> None:
        self._listeners.append(callback)

    def _notify(self) -> None:
        for cb in list(self._listeners):
            try:
                cb()
            except Exception:
                pass

    # MARK: Properties

    @property
    def is_enabled(self) -> bool:
        return self._is_enabled

    @is_enabled.setter
    def is_enabled(self, value: bool) -> None:
        self._is_enabled = value
        self._settings.is_enabled = value
        self._settings.save()
        self._notify()

    @property
    def sound_enabled(self) -> bool:
        return self._sound_enabled

    @sound_enabled.setter
    def sound_enabled(self, value: bool) -> None:
        self._sound_enabled = value
        self._settings.sound_enabled = value
        self._settings.save()
        self._notify()

    @property
    def prompt_queue(self) -> list[str]:
        return self._prompt_queue

    @prompt_queue.setter
    def prompt_queue(self, value: list[str]) -> None:
        self._prompt_queue = value
        self._settings.prompt_queue = value
        self._settings.save()
        self._notify()

    @property
    def current_prompt_index(self) -> int:
        return self._current_prompt_index

    @current_prompt_index.setter
    def current_prompt_index(self, value: int) -> None:
        self._current_prompt_index = value
        self._settings.current_prompt_index = value
        self._settings.save()
        self._notify()

    @property
    def is_prompt_queue_active(self) -> bool:
        return self._is_prompt_queue_active

    @is_prompt_queue_active.setter
    def is_prompt_queue_active(self, value: bool) -> None:
        self._is_prompt_queue_active = value
        self._settings.is_prompt_queue_active = value
        self._settings.save()
        self._notify()

    @property
    def loop_mode_enabled(self) -> bool:
        return self._loop_mode_enabled

    @loop_mode_enabled.setter
    def loop_mode_enabled(self, value: bool) -> None:
        self._loop_mode_enabled = value
        self._settings.loop_mode_enabled = value
        self._settings.save()
        self._notify()

    @property
    def loop_mode_limit(self) -> int:
        return self._loop_mode_limit

    @loop_mode_limit.setter
    def loop_mode_limit(self, value: int) -> None:
        self._loop_mode_limit = value
        self._settings.loop_mode_limit = value
        self._settings.save()
        self._notify()

    @property
    def loop_mode_counter(self) -> int:
        return self._loop_mode_counter

    @loop_mode_counter.setter
    def loop_mode_counter(self, value: int) -> None:
        self._loop_mode_counter = value
        self._settings.loop_mode_counter = value
        self._settings.save()
        self._notify()

    def set_clipboard_callback(self, callback: Callable[[str], None]) -> None:
        self._clipboard_callback = callback

    def reset_prompt_queue_to_default(self) -> None:
        from .settings_store import DEFAULT_PROMPT
        self.prompt_queue = [DEFAULT_PROMPT]
        self.current_prompt_index = 0
        self.is_prompt_queue_active = True

    @property
    def total_approvals_count(self) -> int:
        return self._total_approvals_count

    def get_logs(self) -> list[LogEntry]:
        with self._logs_lock:
            return list(self.logs)

    def stop(self) -> None:
        self._stop_event.set()

    # MARK: Scan loop

    def _run_loop(self) -> None:
        while not self._stop_event.wait(self._scan_interval):
            try:
                self._scan_tick()
            except Exception as e:
                print(f"[ApproverEngine] Scan tick failed: {e}")

    def _scan_tick(self) -> None:
        if not self._is_enabled:
            return
        if time.monotonic() - self._last_action_time < COOLDOWN_SECONDS:
            return

        with self._rules_lock:
            buttons = [r.keyword for r in self.button_rules if r.is_enabled]
            checkboxes = [r.keyword for r in self.checkbox_rules if r.is_enabled]
        if not buttons:
            return

        observer = AppObserver.shared()
        target_apps = observer.find_target_applications()
        
        # Scale scanning interval dynamically to save CPU cycles
        if target_apps:
            self._scan_interval = 1.0  # scan faster (every 1s) when targets are running
        else:
            self._scan_interval = SCAN_INTERVAL_SECONDS  # fall back to 3.0s when idle
            return

        inspector = AtspiInspector.shared()

        for app in target_apps:
            app_name = getattr(app, "name", "") or "Target App"

            # Check if target app is a terminal process and inspect it for confirmation prompts
            if observer.is_terminal(app):
                try:
                    term_response = inspector.inspect_terminal_for_prompts(app, buttons)
                    if term_response:
                        self._last_action_time = time.monotonic()
                        ClickAutomation.shared().send_string(term_response)
                        self._record(app_name, "Terminal Confirmation Prompt", "AT-SPI Terminal")
                        return  # stop after the first successful action this tick
                except Exception as e:
                    print(f"[ApproverEngine] Terminal inspection failed for {app_name}: {e}")

            try:
                result = inspector.inspect_and_auto_approve(app, buttons, checkboxes)
            except Exception as e:
                print(f"[ApproverEngine] Inspection failed for {app_name}: {e}")
                result = None

            if result is not None:
                self._last_action_time = time.monotonic()
                if result.action == "Fallback Click Needed" and result.position is not None:
                    ClickAutomation.shared().perform_click(
                        result.position,
                        lambda a=app_name, t=result.element_text: self._record(a, t, "AT-SPI + Click"),
                    )
                else:
                    self._record(app_name, result.element_text, result.action)
                return  # stop after the first successful action this tick

            # Prompt Queue Check or Loop Mode Check
            should_check_prompt_state = (self._is_prompt_queue_active and self.current_prompt_index < len(self.prompt_queue)) or \
                                         (self.loop_mode_enabled and (self.loop_mode_limit == 0 or self.loop_mode_counter < self.loop_mode_limit))

            if should_check_prompt_state:
                try:
                    windows = observer.top_level_windows(app)
                    if observer.is_browser(app):
                        windows = [w for w in windows if observer.is_antigravity_window(w)]

                    is_busy = False
                    input_area = None
                    for win in windows:
                        chat_state = inspector.find_chat_input_and_status(win, 0)
                        if chat_state.is_busy:
                            is_busy = True
                        if chat_state.input_area is not None:
                            input_area = chat_state.input_area

                    if not is_busy and input_area is not None:
                        prompt = DEFAULT_PROMPT if self.loop_mode_enabled else self.prompt_queue[self.current_prompt_index]
                        self._paste_prompt(prompt, input_area, app)
                        return  # stop after pasting
                except Exception as e:
                    print(f"[ApproverEngine] Prompt queue check failed for {app_name}: {e}")

        # Pass 2: OCR fallback if AT-SPI found nothing
        if self._ocr_scan_in_flight:
            return
        for app in target_apps:
            bounds = observer.get_window_bounds(app)
            if bounds is None:
                continue
            app_name = getattr(app, "name", "") or "Target App"
            self._ocr_scan_in_flight = True
            threading.Thread(target=self._run_ocr_pass, args=(bounds, buttons, app_name), daemon=True).start()
            break

    def _paste_prompt(self, prompt: str, input_area, app) -> None:
        if self.loop_mode_enabled:
            self.loop_mode_counter += 1
            print(f"🤖 Loop Mode: Pasting prompt {self.loop_mode_counter}/{'∞' if self.loop_mode_limit == 0 else self.loop_mode_limit}")
        else:
            self.current_prompt_index += 1
            print(f"🤖 Prompt Queue: Pasting prompt {self.current_prompt_index}/{len(self.prompt_queue)}")

        self._last_action_time = time.monotonic()
        self._notify()

        center = AtspiInspector.shared().center_of(input_area)
        if center is not None:
            print(f"🎯 Clicking center of chat input area at: {center} for app: {getattr(app, 'name', '')}")
            ClickAutomation.shared().perform_click(center, lambda: self._paste_step_2(prompt))

    def _paste_step_2(self, prompt: str) -> None:
        threading.Thread(target=self._paste_worker, args=(prompt,), daemon=True).start()

    def _paste_worker(self, prompt: str) -> None:
        time.sleep(0.25)
        if self._clipboard_callback:
            try:
                self._clipboard_callback(prompt)
            except Exception as e:
                print(f"Clipboard callback failed: {e}")
        else:
            import tkinter as tk
            try:
                r = tk.Tk()
                r.withdraw()
                r.clipboard_clear()
                r.clipboard_append(prompt)
                r.update()
                r.destroy()
            except Exception as e:
                print(f"Fallback clipboard set failed: {e}")

        time.sleep(0.15)
        print("📋 Pasting prompt...")
        ClickAutomation.shared().press_paste_keystroke()
        time.sleep(0.2)
        print("⌨️ Pressing Return key...")
        ClickAutomation.shared().press_return_key()

    def _run_ocr_pass(self, bounds: tuple[int, int, int, int], buttons: list[str], app_name: str) -> None:
        try:
            point, text = OcrScanner.shared().scan_region_for_keywords(bounds, buttons)
            if point is None or text is None:
                return
            if time.monotonic() - self._last_action_time < COOLDOWN_SECONDS:
                return
            self._last_action_time = time.monotonic()
            ClickAutomation.shared().perform_click(point, lambda: self._record(app_name, text, "OCR"))
        finally:
            self._ocr_scan_in_flight = False

    # MARK: Logging & audio feedback

    def _record(self, app_name: str, text: str, method: str) -> None:
        self._total_approvals_count += 1
        self._settings.total_approvals_count = self._total_approvals_count
        self._settings.save()

        entry = LogEntry(app_name=app_name, target_text=text, detection_method=method)
        with self._logs_lock:
            self.logs.insert(0, entry)
            if len(self.logs) > MAX_LOG_ENTRIES:
                del self.logs[MAX_LOG_ENTRIES:]

        if self._sound_enabled:
            self._play_sound()

        self._notify()

    def _play_sound(self) -> None:
        for path in SOUND_CANDIDATES:
            try:
                subprocess.Popen(
                    ["paplay", path],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                return
            except Exception:
                continue

    # MARK: Rule management

    def add_rule(self, keyword: str, target_type: TargetType) -> None:
        kw = keyword.strip()
        if not kw:
            return
        with self._rules_lock:
            collection = self.button_rules if target_type == TargetType.BUTTON else self.checkbox_rules
            if any(r.keyword.lower() == kw.lower() for r in collection):
                return
            collection.append(ApprovalRule(kw, target_type))
        self._save_rules()
        self._notify()

    def remove_rule(self, rule_id: str, target_type: TargetType) -> None:
        with self._rules_lock:
            collection = self.button_rules if target_type == TargetType.BUTTON else self.checkbox_rules
            collection[:] = [r for r in collection if r.id != rule_id]
        self._save_rules()
        self._notify()

    def toggle_rule(self, rule_id: str, target_type: TargetType) -> None:
        with self._rules_lock:
            collection = self.button_rules if target_type == TargetType.BUTTON else self.checkbox_rules
            for r in collection:
                if r.id == rule_id:
                    r.is_enabled = not r.is_enabled
                    break
        self._save_rules()
        self._notify()

    def reset_rules_to_default(self) -> None:
        with self._rules_lock:
            self.button_rules = [ApprovalRule(k, TargetType.BUTTON) for k in DEFAULT_BUTTONS]
            self.checkbox_rules = [ApprovalRule(k, TargetType.CHECKBOX) for k in DEFAULT_CHECKBOXES]
        self._save_rules()
        self._notify()

    def clear_logs(self) -> None:
        with self._logs_lock:
            self.logs.clear()
        self._notify()

    def _save_rules(self) -> None:
        self._settings.button_rules = list(self.button_rules)
        self._settings.checkbox_rules = list(self.checkbox_rules)
        self._settings.save()
