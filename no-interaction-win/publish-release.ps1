# Copies the current dist\ build artifacts into ..\release\win\ as versioned release
# files, replacing whatever was there before — mirroring how release\mac and
# release\linux are kept up to date with their latest build. Called automatically as
# the last step of build-installer.ps1, so release\win\ always reflects the most
# recently built version.
#
# Run standalone with:
#   .\publish-release.ps1

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
    Write-Error "$ExeSource not found — run build.ps1 (or build-installer.ps1) first."
    exit 1
}

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

Write-Host "Publishing v$Version release artifacts to $ReleaseDir..." -ForegroundColor Cyan

# Clear out previous versions so release\win only ever holds the latest build, matching
# release\mac / release\linux (one current set of artifacts, not an accumulating history).
Get-ChildItem -Path $ReleaseDir -Filter "NoInteraction-v*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $ReleaseDir -Filter "NoInteractionSetup-v*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force
$OldUnversionedZip = Join-Path $ReleaseDir "NoInteraction.zip"
if (Test-Path $OldUnversionedZip) { Remove-Item -Force $OldUnversionedZip }

$ZipDest = Join-Path $ReleaseDir "NoInteraction-v$Version.zip"
Compress-Archive -Path $ExeSource -DestinationPath $ZipDest -Force
Write-Host "  -> $ZipDest" -ForegroundColor Green

if (Test-Path $SetupSource) {
    $SetupDest = Join-Path $ReleaseDir "NoInteractionSetup-v$Version.exe"
    Copy-Item -Path $SetupSource -Destination $SetupDest -Force
    Write-Host "  -> $SetupDest" -ForegroundColor Green
} else {
    Write-Host "  (no installer at $SetupSource — skipping NoInteractionSetup-v$Version.exe)" -ForegroundColor Yellow
}

Write-Host "release\win is up to date at v$Version." -ForegroundColor Green
