# NoInteraction (Windows)

Windows port of the macOS NoInteraction app. Watches for Antigravity / VS Code /
browser windows and auto-clicks matching approval buttons (`Allow`, `Approve`,
`Continue`, ...) and auto-ticks matching checkboxes (`Remember`, `Trust`, ...)
using UI Automation, with an OCR fallback for content UI Automation can't see.

This port intentionally does **not** include the Mac build's Prompt Queue /
Loop Mode feature (auto-pasting new prompts into the agent's chat box). It
only automates the approval dialogs themselves.

## Requirements

- Windows 10 (1903+) or Windows 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) to build

## Build

```powershell
.\build.ps1
```

Produces a self-contained `dist\NoInteraction.exe` — no .NET runtime install
needed on the target machine.

## Run

Run `dist\NoInteraction.exe`. It starts in the system tray; left-click the
tray icon to open the dashboard, right-click for the menu (pause/resume,
mute sound, quit).

## Notes

- If the target app (Antigravity / VS Code) is running elevated (as
  Administrator) and NoInteraction isn't, Windows' UI privilege isolation
  (UIPI) will block automation. Run NoInteraction at the same privilege
  level as the app you want it to observe.
- Settings and rules are stored at `%AppData%\NoInteraction\settings.json`.
