$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsprojPath = Join-Path $Root "NoInteraction.csproj"
$DistDir = Join-Path $Root "dist"
$ReleaseDir = Join-Path $Root "..\release\win"

$csprojContent = Get-Content $CsprojPath -Raw
$match = [regex]::Match($csprojContent, '<Version>(\d+\.\d+\.\d+)</Version>')
if (-not $match.Success) {
    Write-Error "Could not find <Version>X.Y.Z</Version> in $CsprojPath"
    exit 1
}
$Version = $match.Groups[1].Value

$ExeSource = Join-Path $DistDir "NoInteraction.exe"
$SetupSource = Join-Path $DistDir "NoInteractionSetup.exe"
if (-not (Test-Path $ExeSource)) {
    Write-Error "$ExeSource not found - run build.ps1 (or build-installer.ps1) first."
    exit 1
}

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

Write-Host "Publishing v$Version release artifacts to $ReleaseDir..." -ForegroundColor Cyan

Get-ChildItem -Path $ReleaseDir -Filter "NoInteraction-v*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $ReleaseDir -Filter "NoInteractionSetup-v*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force

$ZipDest = Join-Path $ReleaseDir "NoInteraction-v$Version.zip"
Compress-Archive -Path $ExeSource -DestinationPath $ZipDest -Force
Write-Host "  -> $ZipDest" -ForegroundColor Green

if (Test-Path $SetupSource) {
    $SetupDest = Join-Path $ReleaseDir "NoInteractionSetup-v$Version.exe"
    Copy-Item -Path $SetupSource -Destination $SetupDest -Force
    Write-Host "  -> $SetupDest" -ForegroundColor Green

    $SetupGeneric = Join-Path $ReleaseDir "NoInteractionSetup.exe"
    Copy-Item -Path $SetupSource -Destination $SetupGeneric -Force
}

$ExeGeneric = Join-Path $ReleaseDir "NoInteraction.exe"
Copy-Item -Path $ExeSource -Destination $ExeGeneric -Force

Write-Host "release\win is up to date at v$Version." -ForegroundColor Green
