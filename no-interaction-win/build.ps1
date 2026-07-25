# Builds a self-contained, single-file NoInteraction.exe for Windows x64.
# Run from PowerShell on Windows with the .NET 8 SDK installed:
#   .\build.ps1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "Restoring & publishing NoInteraction..." -ForegroundColor Cyan

dotnet publish NoInteraction.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o dist

Write-Host "Build complete: dist\NoInteraction.exe" -ForegroundColor Green

Write-Host "Code-signing dist\NoInteraction.exe..." -ForegroundColor Cyan
& "$Root\sign.ps1" -ExePath "$Root\dist\NoInteraction.exe"

