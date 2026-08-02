# NoInteraction (Windows) — Release Artifacts

This folder holds the latest built Windows release, published automatically by
`no-interaction-win\build-installer.ps1` (via `publish-release.ps1`) every time
it's run — the version number always matches the current build.

- **`NoInteractionSetup-v<version>.exe`** — recommended. A double-clickable
  installer (built with Inno Setup): no admin rights needed, installs to
  `%LocalAppData%\Programs\NoInteraction`, adds a Start Menu entry and
  uninstaller, with optional desktop shortcut / launch-at-startup checkboxes.
- **`NoInteraction-v<version>.zip`** — the raw self-contained exe, no
  installer. Unzip and run `NoInteraction.exe` directly; no .NET runtime
  install needed on the target machine.

## Building it yourself

Since compiling Windows WPF applications requires a Windows OS environment,
build from a Windows machine:

1. A computer running **Windows 10/11**.
2. **.NET 8.0 SDK** (or higher) — [dot.net](https://dot.net).
3. **Inno Setup 6** (only needed for the installer) —
   `winget install JRSoftware.InnoSetup`.

From `no-interaction-win/` in PowerShell:

```powershell
.\build-installer.ps1
```

This bumps the version, publishes and signs `dist\NoInteraction.exe`, builds
and signs `dist\NoInteractionSetup.exe`, and republishes both here in
`release\win\`. For just the raw exe without the installer or release
publishing step, run `.\build.ps1` instead.
