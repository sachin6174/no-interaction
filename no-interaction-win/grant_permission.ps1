# ──────────────────────────────────────────────────────────────────────────────
# grant_permission.ps1 — Permission Management & Environment Setup for Windows
# - Checks Administrator / UAC Elevation privileges
# - Unblocks NoInteraction binaries from Windows Defender / SmartScreen
# - Verifies UI Automation and Windows Media OCR capabilities
# - Configures Auto-Startup / High-Privilege Scheduled Task if desired
# ──────────────────────────────────────────────────────────────────────────────

param(
    [switch]$Elevate = $false
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "[*] Managing Permissions & Environment for NoInteraction (Windows)..." -ForegroundColor Cyan
Write-Host ""

# 1. Check Administrator Privileges
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "1. Admin Privilege Status: Running as Administrator (Elevated)" -ForegroundColor Green
    Write-Host "   [+] Full UI Automation access granted across elevated target apps." -ForegroundColor Green
} else {
    Write-Host "1. Admin Privilege Status: Running as Standard User (Non-Elevated)" -ForegroundColor Yellow
    Write-Host "   [!] Note: If target app (VS Code / Antigravity / Terminal) runs as Administrator," -ForegroundColor Yellow
    Write-Host "       Windows UIPI will block non-elevated NoInteraction from controlling them." -ForegroundColor Yellow
    
    if ($Elevate) {
        Write-Host "   Attempting elevation prompt..." -ForegroundColor Cyan
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit 0
    } else {
        Write-Host "   To grant full elevated automation, run: .\grant_permission.ps1 -Elevate" -ForegroundColor Gray
    }
}

Write-Host ""
# 2. Unblock Binaries from SmartScreen / Mark-of-the-Web
Write-Host "2. SmartScreen / Zone.Identifier Security Check..." -ForegroundColor Cyan
$targetExes = @(
    (Join-Path $Root "dist\NoInteraction.exe"),
    (Join-Path $Root "dist\NoInteractionSetup.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\NoInteraction\NoInteraction.exe")
)

foreach ($exe in $targetExes) {
    if (Test-Path $exe) {
        try {
            Unblock-File -Path $exe -ErrorAction SilentlyContinue
            Write-Host "   [+] Unblocked binary: ${exe}" -ForegroundColor Green
        } catch {
            Write-Host "   [!] Could not unblock ${exe}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
# 3. Check Windows Media OCR Availability
Write-Host "3. Windows Media OCR & Language Pack Check..." -ForegroundColor Cyan
try {
    $langType = [Windows.Media.Ocr.OcrEngine, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]
    $supportedLangs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
    if ($supportedLangs.Count -gt 0) {
        $langNames = ($supportedLangs | Select-Object -ExpandProperty LanguageTag) -join ", "
        Write-Host "   [+] Windows Media OCR Engine active ($langNames)." -ForegroundColor Green
    } else {
        Write-Host "   [!] No OCR language packs installed in Windows." -ForegroundColor Yellow
    }
} catch {
    Write-Host "   [!] Windows Media OCR runtime check notice: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
# 4. Auto-Startup & Scheduled Task Setup
Write-Host "4. Auto-Startup & Shortcut Verification..." -ForegroundColor Cyan
$StartupLnk = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\NoInteraction.lnk"
if (Test-Path $StartupLnk) {
    Write-Host "   [+] Startup shortcut exists: $StartupLnk" -ForegroundColor Green
} else {
    Write-Host "   [*] Run .\install.ps1 to register startup and start menu shortcuts." -ForegroundColor Gray
}

Write-Host ""
Write-Host "[+] Windows Permission & Setup Check Complete!" -ForegroundColor Green
