# AGENTS.md — AI Agent Guidelines & Architecture for NoInteraction

This repository uses automated AI coding agents (Antigravity, Codex, etc.) for cross-platform development, automated button clicking, UI Automation, OCR fallbacks, testing, and release management.

---

## 🧭 Repository Overview

**NoInteraction** is an automated consent & approval assistant designed to eliminate repetitive confirmation prompts across multi-platform desktop environments:

| Platform | Location | Stack / Technologies |
| :--- | :--- | :--- |
| **Windows** | `no-interaction-win/` | C# (.NET 8), WPF, WinForms DPI Manifest, Windows UI Automation (UIA), Windows Media OCR / Inno Setup 6 |
| **macOS** | `no-interaction-mac/` | Swift, macOS Accessibility API (`AXUIElement`), Apple Vision OCR |
| **Linux** | `no-interaction-linux/` | Python 3, AT-SPI / pyatspi, X11 / Wayland automation, Tesseract OCR |
| **Releases** | `release/` | Pre-built installers, standalone binaries, and archives for all platforms |

---

## 🤖 Agent Roles & Responsibilities

When agents operate within this workspace, they take on specialized sub-roles:

### 1. Windows Automation Agent
- **Scope:** `no-interaction-win/`
- **Core Engine:** [`ApproverEngine.cs`](file:///c:/Users/sachi/Desktop/no-interaction/no-interaction-win/NoInteraction/Core/ApproverEngine.cs)
- **UI Inspection:** [`UiaInspector.cs`](file:///c:/Users/sachi/Desktop/no-interaction/no-interaction-win/NoInteraction/Core/UiaInspector.cs)
- **OCR Engine:** [`OcrScanner.cs`](file:///c:/Users/sachi/Desktop/no-interaction/no-interaction-win/NoInteraction/Core/OcrScanner.cs)
- **Click Automation:** [`ClickAutomation.cs`](file:///c:/Users/sachi/Desktop/no-interaction/no-interaction-win/NoInteraction/Core/ClickAutomation.cs)
- **Key Invariants:**
  - Support exact labels as well as shortcut labels (e.g. `Allow Alt+Enter`, `Allow (Ctrl+Shift+Enter)`).
  - OCR fallback requires adjacent guard labels for single-word buttons (e.g. `Allow` requires adjacent `Deny`; `Submit` requires adjacent `Skip`) to eliminate false positives.
  - Coordinate clicks must verify process ownership at the target screen point; covered or background windows are skipped.
  - Scan loop debounce: default scan interval 5s, unchanged prompts debounced by 2s.

### 2. Testing & Regression Verification Agent
- **Scope:** `no-interaction-win/Tests/`
- **Command:** `dotnet run --project Tests/RegressionTests.csproj`
- **Responsibilities:**
  - Verify button geometry, pattern matching, rule enable/disable states.
  - Run OCR against fixtures (`allow-prompt.png`, `submit-prompt.png`).
  - Ensure zero regressions before any release.

### 3. Build & Release Engineering Agent
- **Scope:** `no-interaction-win/build-installer.ps1`, `no-interaction-win/publish-release.ps1`, `release/`
- **Responsibilities:**
  - Bump minor versions (`X.Y.Z -> X.(Y+1).0`) synchronously in `NoInteraction.csproj`, `app.manifest`, and `NoInteraction.iss`.
  - Compile self-contained, single-file executable (`NoInteraction.exe`) with embedded runtime.
  - Authenticode code-sign binaries (`sign.ps1`) with SHA256 certificate.
  - Compile Inno Setup 6 installer wizard (`NoInteractionSetup.exe`) and code-sign.
  - Synchronize release artifacts to `release/win/`.
  - Create git annotated tag (`vX.Y.Z`) and publish to GitHub Releases via REST API with uploaded binary assets.

---

## 🛠️ Common Commands

### Windows Development & Testing
```powershell
# Run regression tests
cd no-interaction-win
dotnet run --project Tests/RegressionTests.csproj

# Build standalone signed executable
.\build.ps1

# Full release build: bumps version, builds exe, compiles Inno installer, signs all, updates release/win
.\build-installer.ps1
```

### Git & Release Workflow
```powershell
# Verify status and track release binaries
git status
git add .
git commit -m "fix(win): description of change"
git push origin main

# Tag and release
git tag -a v1.16.0 -m "Release v1.16.0"
git push origin v1.16.0
```

---

## 📜 Conversation & Audit History

All agent instructions, user prompts, diagnostic runs, and release logs across development iterations are preserved in:
- [`conversation.md`](file:///c:/Users/sachi/Desktop/no-interaction/conversation.md) — Unified historical record of all agent interactions.
