# Installs NoInteraction.exe on Windows:
# - Places executable in %LocalAppData%\Programs\NoInteraction\
# - Code-signs the binary with SHA256 Authenticode signature
# - Creates Start Menu and Auto-Startup shortcuts
# - Launches NoInteraction

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceExe = Join-Path $Root "dist\NoInteraction.exe"

if (-not (Test-Path $SourceExe)) {
    Write-Host "Publishing NoInteraction first..." -ForegroundColor Cyan
    & "$Root\build.ps1"
}

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\NoInteraction"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$TargetExe = Join-Path $InstallDir "NoInteraction.exe"

# Stop existing running instance if any
$existingProc = Get-Process -Name "NoInteraction" -ErrorAction SilentlyContinue
if ($existingProc) {
    Write-Host "Stopping running NoInteraction instance..." -ForegroundColor Yellow
    Stop-Process -Name "NoInteraction" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

Write-Host "Copying executable to $InstallDir..." -ForegroundColor Cyan
Copy-Item -Path $SourceExe -Destination $TargetExe -Force

Write-Host "Code-signing installed executable..." -ForegroundColor Cyan
& "$Root\sign.ps1" -ExePath $TargetExe

Write-Host "Creating Start Menu & Startup shortcuts..." -ForegroundColor Cyan
$WScriptShell = New-Object -ComObject WScript.Shell

# Start Menu Shortcut
$StartMenuShortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\NoInteraction.lnk"
$Shortcut = $WScriptShell.CreateShortcut($StartMenuShortcutPath)
$Shortcut.TargetPath = $TargetExe
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "NoInteraction Auto Approver for Windows"
$Shortcut.Save()

# Auto-Startup Shortcut
$StartupShortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\NoInteraction.lnk"
$StartupShortcut = $WScriptShell.CreateShortcut($StartupShortcutPath)
$StartupShortcut.TargetPath = $TargetExe
$StartupShortcut.WorkingDirectory = $InstallDir
$StartupShortcut.Description = "NoInteraction Auto Approver for Windows"
$StartupShortcut.Save()

Write-Host "Installation Complete! Launching NoInteraction..." -ForegroundColor Green
Start-Process -FilePath $TargetExe
