# NoInteraction (Linux)

Linux port of the macOS NoInteraction app. Watches for Antigravity / VS Code /
browser windows and auto-clicks matching approval buttons (`Allow`, `Approve`,
`Continue`, ...) and auto-ticks matching checkboxes (`Remember`, `Trust`, ...)
using AT-SPI, with a Tesseract OCR fallback for content AT-SPI can't see.

This port includes the macOS build's Prompt Queue / Loop Mode feature (auto-pasting new prompts into the agent's chat box) in addition to automating the approval dialogs themselves.

## Requirements

Debian/Ubuntu:

```bash
sudo apt install python3 python3-venv python3-gi python3-pyatspi \
                  gir1.2-ayatanaappindicator3-0.1 python3-tk \
                  tesseract-ocr
```

- `python3-pyatspi` / `python3-gi` — accessibility tree access (AT-SPI2)
- `gir1.2-ayatanaappindicator3-0.1` — tray icon backend for pystray (use
  `gir1.2-appindicator3-0.1` on older distros if the ayatana package isn't
  available)
- `python3-tk` — the dashboard UI
- `tesseract-ocr` — OCR fallback

## Run

```bash
./run.sh
```

This creates a `--system-site-packages` virtualenv (so it can see the
system's `pyatspi`/`gi`, which aren't reliably pip-installable), installs the
remaining pip dependencies, and starts the app. It opens in the system tray;
click the tray icon for the menu (Open Dashboard, pause/resume, mute sound,
quit).

To start automatically at login, copy `no-interaction.desktop` to
`~/.config/autostart/` and edit the `Exec=` line to point at this directory.

## Known Linux-specific limitations

- **AT-SPI must be enabled for the target app.** GTK apps expose an
  accessibility tree automatically. Electron/Chromium apps (VS Code,
  Antigravity, browsers) only build theirs once an AT-SPI client shows up on
  the session bus — if a target app was already running before you started
  NoInteraction, you may need to restart that app once.
- **The OCR/click fallback needs X11** (or XWayland). It uses the XTest
  extension, which has no Wayland equivalent. The primary AT-SPI path is
  unaffected either way.
- **Tray icon click behavior varies by desktop.** Most Linux tray
  backends (AppIndicator/Ayatana) always open the menu on click — there's no
  separate "left-click for dashboard" behavior like on macOS/Windows. Use
  "Open Dashboard..." from the menu.

Settings and rules are stored at `~/.config/no-interaction/settings.json`.
