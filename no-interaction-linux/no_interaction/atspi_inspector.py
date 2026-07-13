"""AT-SPI equivalent of the Mac build's AXInspector: walks the accessibility
tree of a target application, auto-ticks matching checkboxes, and auto-invokes
the first matching approval button."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pyatspi

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


class AtspiInspector:
    _instance: Optional["AtspiInspector"] = None

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

    # MARK: Pass 1 — checkbox ticking

    def _tick_checkboxes(self, element, depth: int, keywords: list[str]) -> None:
        if depth > MAX_DEPTH:
            return
        role = self._safe_role(element)
        if role is None or self._is_ignored(element, role):
            return

        if role in (pyatspi.ROLE_CHECK_BOX, pyatspi.ROLE_RADIO_BUTTON):
            label = self._label(element)
            if any(KeywordMatcher.matches(label, k) for k in keywords):
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
            is_match = bool(label) and any(KeywordMatcher.matches(label, k) for k in keywords)

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
