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

## Install

Grab `NoInteractionSetup.exe` and double-click it. It's a normal Windows
installer (built with [Inno Setup](https://jrsoftware.org/isinfo.php)) — no
admin rights or .NET install needed, since it installs per-user under
`%LocalAppData%\Programs\NoInteraction` and ships as a self-contained exe.
It adds a Start Menu entry and uninstaller, with optional checkboxes for a
desktop shortcut and launching at Windows startup.

To build the installer yourself:

```powershell
.\build-installer.ps1
```

Requires the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
and [Inno Setup 6](https://jrsoftware.org/isdl.php)
(`winget install JRSoftware.InnoSetup`). Produces `dist\NoInteractionSetup.exe`.

## Build (without the installer)

```powershell
.\build.ps1
```

Produces a self-contained `dist\NoInteraction.exe` directly — no .NET
runtime install needed on the target machine, but no Start Menu entry or
uninstaller either; just the raw exe.

## Run

Launch it from the Start Menu shortcut (if installed) or run
`dist\NoInteraction.exe` directly. It starts in the system tray; left-click
the tray icon to open the dashboard, right-click for the menu (pause/resume,
mute sound, quit).

## Notes

- If the target app (Antigravity / VS Code) is running elevated (as
  Administrator) and NoInteraction isn't, Windows' UI privilege isolation
  (UIPI) will block automation. Run NoInteraction at the same privilege
  level as the app you want it to observe.
- Settings and rules are stored at `%AppData%\NoInteraction\settings.json`.
