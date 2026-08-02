# NoInteraction (Windows) 🛡️

![NoInteraction Version](https://img.shields.io/badge/version-v1.4.0-cba6f7?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-89b4fa?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-a6e3a1?style=flat-square)

Windows desktop application for **NoInteraction** — providing **1:1 feature parity with macOS**. It automatically monitors Antigravity, VS Code, terminal sessions, and browser windows to auto-approve confirmation dialogs, tick consent checkboxes, and dispatch sequential prompt queues without manual intervention.

---

## ✨ Features

- **1:1 macOS Feature Parity**: Full feature set matching `no-interaction-mac`.
- **4 Interactive Dashboard Tabs**:
  - **Activity Log**: Real-time audit log, search filtering, detection method badges (`UIA + WinClick`, `Vision OCR`), and timestamps.
  - **Approval Rules**: Custom verification bypass management with interactive toggle/delete keyword chips for buttons and checkboxes.
  - **Prompt Queue**: Queue dispatch toggle, Loop Test Mode (Infinite / 10 Iteration counter), system audit prompt template, custom prompt editor, and prompt queue list.
  - **Terminals**: Automatic terminal session detection and auto-return prompt handler for Windows Terminal and PowerShell.
- **Dual Approval Engine**:
  - **Windows UI Automation (UIA)**: High-speed native tree traversal and programmatic element clicking.
  - **Vision OCR Fallback**: Optical Character Recognition for non-standard or canvas-rendered UI elements.
- **Authenticode Code-Signed**: Built with an embedded Authenticode signature to run smoothly without Windows SmartScreen warnings.
- **Catppuccin Dark GUI**: Modern WPF dashboard window with custom titlebar icon, sound toggles, status shield, and system tray integration.

---

## 🚀 Installation & Usage

### 📦 Pre-built Executable
1. Download `NoInteraction-v1.4.0.zip` or `NoInteraction.exe` from the [Latest Release](https://github.com/sachin6174/no-interaction/releases).
2. Run `NoInteraction.exe`. The app will launch directly into the center of your screen and dock into your Windows System Tray.

### 🛠️ Build from Source
Requirements:
- Windows 10 (1903+) or Windows 11
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

Run the build script:
```powershell
.\build.ps1
```
This produces a self-contained `dist\NoInteraction.exe` executable with embedded code-signing.

---

## ⚙️ Configuration & Storage
Settings, prompt queues, and custom rules are automatically persisted in JSON format at:
`%AppData%\NoInteraction\settings.json`
