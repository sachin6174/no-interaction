"""AT-SPI equivalent of the Mac build's AXInspector: walks the accessibility
tree of a target application, auto-ticks matching checkboxes, and auto-invokes
the first matching approval button."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pyatspi
import re


from .app_observer import AppObserver
from .models import KeywordMatcher

def _roles(*names: str) -> set:
    """Looks up role constants by name, skipping any that don't exist in this
    pyatspi version rather than crashing the whole module at import time."""
    return {r for r in (getattr(pyatspi, n, None) for n in names) if r is not None}


IGNORED_ROLES = _roles("ROLE_TREE", "ROLE_TREE_TABLE", "ROLE_TABLE", "ROLE_PAGE_TAB_LIST")
LABEL_ROLES = _roles("ROLE_LABEL", "ROLE_STATIC", "ROLE_TEXT", "ROLE_HEADING")
BLOCKED_SUBSTRINGS = ("sidebar", "explorer", "outline", "navigation", "tab bar")

MAX_DEPTH = 25


@dataclass
class InspectionResult:
    action: str
    element_text: str
    position: Optional[tuple[int, int]]


@dataclass
class ChatStateResult:
    input_area: Optional[any] = None
    is_busy: bool = False


class AtspiInspector:
    _instance: Optional["AtspiInspector"] = None

    def __init__(self):
        self._last_terminal_prompts: dict[int, str] = {}

    @classmethod
    def shared(cls) -> "AtspiInspector":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def inspect_and_auto_approve(self, app, button_keywords: list[str], checkbox_keywords: list[str]) -> Optional[InspectionResult]:
        observer = AppObserver.shared()
        windows = observer.top_level_windows(app)
        if not windows:
            return None

        if observer.is_browser(app):
            filtered = [w for w in windows if observer.is_antigravity_window(w)]
            if filtered:
                windows = filtered

        if checkbox_keywords:
            for win in windows:
                self._tick_checkboxes(win, 0, checkbox_keywords)

        all_keywords = button_keywords + checkbox_keywords
        for win in windows:
            has_selection = self._is_any_radio_selected(win, 0, all_keywords)
            result = self._find_and_press_button(win, 0, button_keywords, has_selection)
            if result is not None:
                return result
        return None

    def _match_keyword(self, label: str, keyword: str) -> bool:
        kw = keyword.strip()
        lbl = label.strip()
        if not kw or not lbl:
            return False
        if " " in kw:
            return KeywordMatcher.matches(lbl, kw)
        else:
            return lbl.lower() == kw.lower()

    # MARK: Pass 1 — checkbox ticking

    def _tick_checkboxes(self, element, depth: int, keywords: list[str]) -> None:
        if depth > MAX_DEPTH:
            return
        role = self._safe_role(element)
        if role is None or self._is_ignored(element, role):
            return

        if role in (pyatspi.ROLE_CHECK_BOX, pyatspi.ROLE_RADIO_BUTTON):
            label = self._label(element)
            if any(self._match_keyword(label, k) for k in keywords):
                if self._is_checked(element):
                    pass
                elif self._activate(element):
                    print(f"[AtspiInspector] Ticked checkbox/radio '{label}'")

        for child in self._children(element):
            self._tick_checkboxes(child, depth + 1, keywords)

    # MARK: Pass 2 — button pressing

    def _find_and_press_button(self, element, depth: int, keywords: list[str], has_selection: bool) -> Optional[InspectionResult]:
        if depth > MAX_DEPTH:
            return None
        role = self._safe_role(element)
        if role is None or self._is_ignored(element, role):
            return None

        if role in (pyatspi.ROLE_PUSH_BUTTON, pyatspi.ROLE_RADIO_BUTTON, pyatspi.ROLE_TOGGLE_BUTTON):
            if role == pyatspi.ROLE_RADIO_BUTTON and has_selection:
                return None

            label = self._label(element)
            is_match = bool(label) and any(self._match_keyword(label, k) for k in keywords)

            if is_match:
                display = label or "Approval Button"
                center = self._center_of(element)

                if self._activate(element):
                    role_name = self._safe_role_name(element)
                    print(f"[AtspiInspector] Activated '{display}' (role={role_name}, depth={depth})")
                    return InspectionResult("AT-SPI Action", display, center)
                if center is not None:
                    print(f"[AtspiInspector] Action failed for '{display}', requesting fallback click at {center}")
                    return InspectionResult("Fallback Click Needed", display, center)

        for child in self._children(element):
            result = self._find_and_press_button(child, depth + 1, keywords, has_selection)
            if result is not None:
                return result
        return None

    def _is_any_radio_selected(self, element, depth: int, keywords: list[str]) -> bool:
        if depth > MAX_DEPTH:
            return False
        role = self._safe_role(element)
        if role is None or self._is_ignored(element, role):
            return False

        if role in (pyatspi.ROLE_RADIO_BUTTON, pyatspi.ROLE_CHECK_BOX):
            label = self._label(element)
            if label and any(KeywordMatcher.matches(label, k) for k in keywords):
                if self._is_checked(element):
                    return True

        for child in self._children(element):
            if self._is_any_radio_selected(child, depth + 1, keywords):
                return True
        return False

    # MARK: Helpers

    def _is_ignored(self, element, role) -> bool:
        if role in IGNORED_ROLES:
            return True
        name = (getattr(element, "name", "") or "").lower()
        try:
            desc = (element.description or "").lower()
        except Exception:
            desc = ""
        haystack = name + " " + desc
        return any(b in haystack for b in BLOCKED_SUBSTRINGS)

    def _safe_role(self, element):
        try:
            return element.getRole()
        except Exception:
            return None

    def _safe_role_name(self, element) -> str:
        try:
            return element.getRoleName()
        except Exception:
            return "unknown"

    def _label(self, element) -> str:
        text = (getattr(element, "name", "") or "").strip()
        if not text:
            for child in self._children(element):
                role = self._safe_role(child)
                if role in LABEL_ROLES:
                    child_text = (getattr(child, "name", "") or "").strip()
                    if child_text:
                        text = f"{text} {child_text}".strip() if text else child_text
        return text.strip()

    def _children(self, element) -> list:
        children = []
        try:
            for i in range(element.childCount):
                try:
                    children.append(element.getChildAtIndex(i))
                except Exception:
                    continue
        except Exception:
            pass
        return children

    def _is_checked(self, element) -> bool:
        try:
            return element.getState().contains(pyatspi.STATE_CHECKED)
        except Exception:
            return False

    def _activate(self, element) -> bool:
        """Invokes the element's default AT-SPI action (click/press/toggle)."""
        try:
            action = element.queryAction()
            if action.getNActions() > 0:
                return bool(action.doAction(0))
        except Exception:
            pass
        return False

    def center_of(self, element) -> Optional[tuple[int, int]]:
        return self._center_of(element)

    def _center_of(self, element) -> Optional[tuple[int, int]]:
        rect = AppObserver.shared().extents(element)
        if rect is None:
            return None
        x, y, w, h = rect
        if w <= 0 or h <= 0:
            return None
        return (x + w // 2, y + h // 2)

    def find_chat_input_and_status(self, element, depth: int = 0) -> ChatStateResult:
        result = ChatStateResult()

        def traverse(el, current_depth):
            if current_depth > 30:
                return

            role = self._safe_role(el)
            if role is None:
                return

            # Check for Stop button
            is_button = False
            try:
                is_button = role in (
                    getattr(pyatspi, "ROLE_PUSH_BUTTON", None),
                    getattr(pyatspi, "ROLE_TOGGLE_BUTTON", None),
                    getattr(pyatspi, "ROLE_BUTTON", None)
                )
            except Exception:
                pass

            if is_button:
                label = self._label(el).lower().strip()
                try:
                    desc = (el.description or "").lower().strip()
                except Exception:
                    desc = ""

                is_stop = any(
                    x in label or x in desc
                    for x in ("stop", "cancel", "stop generating", "interrupt", "■", "⏹", "square.fill", "stop.fill")
                )
                if is_stop:
                    result.is_busy = True

            # Check for Text Entry (chat input)
            is_text_entry = False
            try:
                is_text_entry = role in (
                    getattr(pyatspi, "ROLE_ENTRY", None),
                    getattr(pyatspi, "ROLE_TEXT", None)
                )
            except Exception:
                pass

            if is_text_entry:
                label = (getattr(el, "name", "") or "").lower().strip()
                try:
                    desc = (el.description or "").lower().strip()
                except Exception:
                    desc = ""

                placeholder = ""
                try:
                    attrs = el.getAttributes()
                    for attr in attrs:
                        if attr.startswith("placeholder-text="):
                            placeholder = attr.split("=", 1)[1].lower()
                except Exception:
                    pass

                is_chat_input = any(
                    x in label or x in desc or x in placeholder
                    for x in ("message", "ask", "prompt", "type a", "ask a", "chat")
                )
                if is_chat_input:
                    result.input_area = el

            for child in self._children(el):
                traverse(child, current_depth + 1)

        traverse(element, depth)
        return result

    # MARK: Pass 3 — Terminal monitoring

    def inspect_terminal_for_prompts(self, app, button_keywords: list[str]) -> Optional[str]:
        observer = AppObserver.shared()
        windows = observer.top_level_windows(app)
        if not windows:
            return None

        # Matches standard prompts like:
        # "Are you sure you want to continue connecting (yes/no/[fingerprint])?"
        # "Do you want to continue? [y/N]"
        # "Proceed? (y/n)"
        prompt_pattern = re.compile(
            r"(?i)(are you sure you want to continue connecting|do you want to continue|proceed with installation|accept the license|apply changes|proceed|continue)\??\s*[\(\[]\s*(yes/no/\[fingerprint\]|yes/no|y/n|y/n/\[fingerprint\]|y/n/c|y/n/a)\s*[\)\]]\s*$",
            re.IGNORECASE
        )

        for win in windows:
            terminals = self._find_terminals(win, 0)
            for term in terminals:
                try:
                    text_iface = term.queryText()
                except Exception:
                    continue

                if text_iface is None:
                    continue

                try:
                    count = text_iface.characterCount
                    if count <= 0:
                        continue
                    # Fetch only the last 200 characters to keep it highly performant
                    start_idx = max(0, count - 200)
                    buffer_text = text_iface.getText(start_idx, count).strip()
                except Exception:
                    continue

                if not buffer_text:
                    continue

                # Get the last non-empty line
                lines = [l.strip() for l in buffer_text.split('\n') if l.strip()]
                if not lines:
                    continue
                last_line = lines[-1]

                # Match the last line against our regex patterns
                match = prompt_pattern.search(last_line)
                if match:
                    question = match.group(1).lower()
                    choices = match.group(2).lower()

                    # Default to y, or yes if explicitly asked for yes/no
                    response = "y\n"
                    if "yes/no" in choices:
                        response = "yes\n"

                    # Check standard safe contexts or user-configured keywords
                    is_standard_safe = any(
                        kw in question for kw in
                        ["proceed", "continue", "install", "accept", "trust", "connect", "allow", "confirm", "yes/no"]
                    )
                    is_user_matched = any(kw.lower() in question for kw in button_keywords)

                    if is_standard_safe or is_user_matched:
                        term_id = id(term)
                        # Debounce: avoid replying to the exact same prompt line
                        if self._last_terminal_prompts.get(term_id) == last_line:
                            continue

                        self._last_terminal_prompts[term_id] = last_line
                        print(f"[AtspiInspector] Detected terminal prompt: '{last_line}' -> Auto-responding '{response.strip()}'")
                        return response
        return None

    def _find_terminals(self, element, depth: int = 0) -> list:
        if depth > MAX_DEPTH:
            return []
        role = self._safe_role(element)
        if role is None:
            return []

        terminals = []
        try:
            if role == pyatspi.ROLE_TERMINAL:
                terminals.append(element)
        except Exception:
            pass

        for child in self._children(element):
            terminals.extend(self._find_terminals(child, depth + 1))
        return terminals

