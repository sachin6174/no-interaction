# Bumps the minor version (X.Y.Z -> X.(Y+1).0) and writes it back everywhere the
# version number needs to stay in sync: the csproj, the app manifest, and the
# installer script. Called automatically by build.ps1 on every build, so every
# published exe/installer carries a fresh version number.
#
# Run standalone with:
#   .\bump-version.ps1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CsprojPath = Join-Path $Root "NoInteraction.csproj"
$ManifestPath = Join-Path $Root "NoInteraction\App\app.manifest"
$IssPath = Join-Path $Root "installer\NoInteraction.iss"

$csprojContent = Get-Content $CsprojPath -Raw
$match = [regex]::Match($csprojContent, '<Version>(\d+)\.(\d+)\.(\d+)</Version>')
if (-not $match.Success) {
    Write-Error "Could not find <Version>X.Y.Z</Version> in $CsprojPath"
    exit 1
}

$major = [int]$match.Groups[1].Value
$oldMinor = [int]$match.Groups[2].Value
$oldPatch = [int]$match.Groups[3].Value
$minor = $oldMinor + 1
$NewVersion = "$major.$minor.0"
$NewFileVersion = "$NewVersion.0"

Write-Host "Bumping version: $major.$oldMinor.$oldPatch -> $NewVersion" -ForegroundColor Cyan

$csprojContent = $csprojContent -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"
$csprojContent = $csprojContent -replace '<AssemblyVersion>\d+\.\d+\.\d+\.\d+</AssemblyVersion>', "<AssemblyVersion>$NewFileVersion</AssemblyVersion>"
$csprojContent = $csprojContent -replace '<FileVersion>\d+\.\d+\.\d+\.\d+</FileVersion>', "<FileVersion>$NewFileVersion</FileVersion>"
Set-Content -Path $CsprojPath -Value $csprojContent -NoNewline

$manifestContent = Get-Content $ManifestPath -Raw
$manifestContent = $manifestContent -replace 'assemblyIdentity version="\d+\.\d+\.\d+\.\d+"', ('assemblyIdentity version="' + $NewFileVersion + '"')
Set-Content -Path $ManifestPath -Value $manifestContent -NoNewline

if (Test-Path $IssPath) {
    $issContent = Get-Content $IssPath -Raw
    $issContent = $issContent -replace '#define MyAppVersion "\d+\.\d+\.\d+"', ('#define MyAppVersion "' + $NewVersion + '"')
    Set-Content -Path $IssPath -Value $issContent -NoNewline
}

Write-Host "Version bumped to $NewVersion (file version $NewFileVersion)" -ForegroundColor Green
Write-Output $NewVersion
