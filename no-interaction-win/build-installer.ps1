# Builds dist\NoInteractionSetup.exe: a double-clickable installer that publishes,
# signs, and packages NoInteraction.exe via Inno Setup.
# Run from PowerShell on Windows with the .NET 8 SDK and Inno Setup 6 installed:
#   .\build-installer.ps1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "Step 1/2: Publishing & signing NoInteraction.exe..." -ForegroundColor Cyan
& "$Root\build.ps1"

Write-Host "Step 2/2: Compiling installer with Inno Setup..." -ForegroundColor Cyan

$IsccCandidates = @(
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) {
    $found = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($found) { $Iscc = $found.Source }
}
if (-not $Iscc) {
    Write-Error "Inno Setup 6 (ISCC.exe) not found. Install it first: winget install JRSoftware.InnoSetup"
    exit 1
}

& $Iscc "$Root\installer\NoInteraction.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed with exit code $LASTEXITCODE."
    exit 1
}

$SetupExe = Join-Path $Root "dist\NoInteractionSetup.exe"
Write-Host "Code-signing $SetupExe..." -ForegroundColor Cyan
& "$Root\sign.ps1" -ExePath $SetupExe

Write-Host "Installer ready: $SetupExe" -ForegroundColor Green
