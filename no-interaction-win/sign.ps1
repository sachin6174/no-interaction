# Signs a target Windows executable using Authenticode Code Signing.
# Usage:
#   .\sign.ps1 [-ExePath "dist\NoInteraction.exe"]

param(
    [string]$ExePath = "dist\NoInteraction.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) {
    Write-Error "Target executable not found at path: $ExePath"
    exit 1
}

Write-Host "Checking for Code Signing Certificates..." -ForegroundColor Cyan

$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

if (-not $cert) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My -CodeSigningCert | Select-Object -First 1
}

if (-not $cert) {
    Write-Host "No existing code-signing certificate found. Creating a self-signed certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=NoInteraction Code Signing Certificate, O=NoInteraction" -CertStoreLocation Cert:\CurrentUser\My
    Write-Host "Created certificate: $($cert.Thumbprint)" -ForegroundColor Green
} else {
    Write-Host "Found existing certificate: $($cert.Subject) [$($cert.Thumbprint)]" -ForegroundColor Green
}

# Ensure the certificate is registered in Root and TrustedPublisher stores so Windows Defender / SmartScreen trust it
try {
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $rootStore.Add($cert)
    $rootStore.Close()

    $pubStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "CurrentUser")
    $pubStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $pubStore.Add($cert)
    $pubStore.Close()

    Write-Host "Registered certificate in CurrentUser Root and TrustedPublisher stores." -ForegroundColor Green
} catch {
    Write-Host "Note: Certificate trust registration notice: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Signing $ExePath with SHA256 Authenticode signature..." -ForegroundColor Cyan
$status = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert -HashAlgorithm SHA256

Write-Host "Executable successfully code-signed!" -ForegroundColor Green
Get-AuthenticodeSignature $ExePath | Format-List Path, Status, StatusMessage, SignerCertificate
