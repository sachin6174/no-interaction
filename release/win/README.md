# NoInteraction (Windows) — Compilation Instructions

Since compiling Windows WPF applications requires a Windows OS environment, you can compile the self-contained, single-file executable using the pre-configured script from a Windows machine.

## Prerequisites

1. A computer running **Windows 10/11**.
2. **.NET 8.0 SDK** (or higher) installed. Download from: [dot.net](https://dot.net).

## How to Build

1. Copy the `no-interaction-win/` directory to your Windows machine.
2. Open **PowerShell** in the `no-interaction-win/` directory.
3. Run the following command to build the executable:
   ```powershell
   .\build.ps1
   ```

4. Once compiled, a standalone executable will be generated at:
   ```
   no-interaction-win\dist\NoInteraction.exe
   ```

You can copy `NoInteraction.exe` anywhere and start using it directly!
