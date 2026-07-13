"""Tesseract-based OCR fallback scanner — the Linux equivalent of the Mac
build's Vision-based VisionOCRScanner. Used only when AT-SPI can't see a
button (e.g. it's rendered inside a canvas/custom-drawn surface)."""

from __future__ import annotations

from typing import Optional

from .models import KeywordMatcher


import threading

class OcrScanner:
    _instance: Optional["OcrScanner"] = None

    @classmethod
    def shared(cls) -> "OcrScanner":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._last_hash = None
        self._lock = threading.Lock()

    def scan_region_for_keywords(
        self, window_bounds: tuple[int, int, int, int], button_keywords: list[str]
    ) -> tuple[Optional[tuple[int, int]], Optional[str]]:
        x, y, w, h = self._button_strip_rect(window_bounds)
        if w <= 0 or h <= 0:
            return None, None

        try:
            import mss
            from PIL import Image
            import hashlib

            with mss.mss() as sct:
                shot = sct.grab({"left": x, "top": y, "width": w, "height": h})
                
                # Check MD5 hash of raw screen data to skip OCR if unchanged
                raw_bytes = shot.raw
                current_hash = hashlib.md5(raw_bytes).hexdigest()
                
                with self._lock:
                    if self._last_hash == current_hash:
                        return None, None
                    self._last_hash = current_hash
                
                img = Image.frombytes("RGB", shot.size, shot.rgb)
        except Exception as e:
            print(f"[OcrScanner] Screen capture failed: {e}")
            return None, None

        try:
            import pytesseract

            data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
        except Exception as e:
            print(f"[OcrScanner] OCR failed: {e}")
            return None, None

        lines: dict[tuple[int, int, int], list[int]] = {}
        n = len(data.get("text", []))
        for i in range(n):
            text = (data["text"][i] or "").strip()
            if not text:
                continue
            key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
            lines.setdefault(key, []).append(i)

        for idxs in lines.values():
            words = [data["text"][i].strip() for i in idxs if data["text"][i].strip()]
            line_text = " ".join(words)
            if not line_text or len(line_text) > 40:
                continue
            if not any(KeywordMatcher.matches(line_text, k) for k in button_keywords):
                continue

            min_x = min(data["left"][i] for i in idxs)
            max_x = max(data["left"][i] + data["width"][i] for i in idxs)
            min_y = min(data["top"][i] for i in idxs)
            max_y = max(data["top"][i] + data["height"][i] for i in idxs)

            screen_x = x + (min_x + max_x) // 2
            screen_y = y + (min_y + max_y) // 2

            print(f"[OcrScanner] Found '{line_text}' at ({screen_x}, {screen_y})")
            return (screen_x, screen_y), line_text

        return None, None

    def _button_strip_rect(self, bounds: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        """Returns only the bottom ~30% of the window — where approval buttons live."""
        x, y, w, h = bounds
        strip_h = max(80, int(h * 0.30))
        return (x, y + h - strip_h, w, strip_h)
