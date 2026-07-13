"""Data models + keyword matcher — mirrors the Mac build's Models.swift so rule
behavior (word-boundary matching, case-insensitivity) is identical across platforms."""

from __future__ import annotations

import re
import threading
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class TargetType(str, Enum):
    BUTTON = "Button"
    CHECKBOX = "Checkbox"


@dataclass
class ApprovalRule:
    keyword: str
    target_type: TargetType
    is_enabled: bool = True
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "keyword": self.keyword,
            "isEnabled": self.is_enabled,
            "targetType": self.target_type.value,
        }

    @staticmethod
    def from_dict(d: dict) -> "ApprovalRule":
        return ApprovalRule(
            id=d.get("id", str(uuid.uuid4())),
            keyword=d["keyword"],
            is_enabled=d.get("isEnabled", True),
            target_type=TargetType(d.get("targetType", "Button")),
        )


@dataclass
class LogEntry:
    app_name: str
    target_text: str
    detection_method: str
    action_taken: str = "Auto-Approved"
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: float = field(default_factory=time.time)

    @property
    def formatted_time(self) -> str:
        return time.strftime("%I:%M:%S %p", time.localtime(self.timestamp))


class KeywordMatcher:
    """Case-insensitive substring match with a word-boundary regex fallback."""

    _lock = threading.Lock()
    _cache: dict[str, re.Pattern] = {}

    @classmethod
    def matches(cls, label: str, keyword: str) -> bool:
        kw = keyword.strip()
        if not kw or not label:
            return False

        if kw.lower() not in label.lower():
            return False

        if label.strip().lower() == kw.lower():
            return True

        with cls._lock:
            pattern = cls._cache.get(kw.lower())
            if pattern is None:
                pattern = re.compile(r"\b" + re.escape(kw) + r"\b", re.IGNORECASE)
                cls._cache[kw.lower()] = pattern

        return pattern.search(label) is not None

    @classmethod
    def clear_cache(cls) -> None:
        with cls._lock:
            cls._cache.clear()
