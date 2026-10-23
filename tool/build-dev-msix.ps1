# Builds a locally signed MSIX with the Store identity and installs it, so the
# Microsoft Store purchase flow can be tested without a package flight.
#
# pubspec.yaml sets `store: true`, which msix cannot be told to override from
# the command line (`--store false` is read as a bare `--store`) and which
# yields an UNSIGNED package. This script flips it off for the build only.
#
# One-time setup, in an ADMINISTRATOR PowerShell, the first time (or whenever
# the certificate is regenerated - the script prints the exact command):
#   Import-Certificate -FilePath "$env:TEMP\synctogether-dev-cert\dev.cer" `
#     -CertStoreLocation Cert:\LocalMachine\TrustedPeople
#
# Usage: ./tool/build-dev-msix.ps1 [-EnvFile .env] [-SkipBuild] [-NoInstall]
param(
  [string]$EnvFile = '.env',
  [switch]$SkipBuild,
  [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..")

$subject = 'CN=C6708BF8-1F72-4C1B-BCDB-C05875ADF7E6' # pubspec msix_config.publisher
$certDir = Join-Path $env:TEMP 'synctogether-dev-cert'
$pfx = Join-Path $certDir 'dev.pfx'
$cer = Join-Path $certDir 'dev.cer'
$password = 'devpass' # throwaway: the certificate only signs local test packages
$outDir = 'build\windows\x64\runner\Release'
$msix = Join-Path $outDir 'synctogether-dev.msix'

if (-not (Test-Path $pfx)) {
  New-Item -ItemType Directory -Force $certDir | Out-Null
  $cert = New-SelfSignedCertificate -Type Custom -Subject $subject -KeyUsage DigitalSignature `
    -FriendlyName 'SyncTogether dev' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(1) `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
  $secure = ConvertTo-SecureString $password -Force -AsPlainText
  Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
  Export-Certificate -Cert $cert -FilePath $cer | Out-Null
  Write-Host "New certificate created. Trust it ONCE from an Administrator PowerShell, then re-run:" -ForegroundColor Yellow
  Write-Host "  Import-Certificate -FilePath `"$cer`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
  exit 1
}

if (-not $SkipBuild) {
  fvm flutter build windows --release "--dart-define-from-file=$EnvFile" --dart-define=STORE_BUILD=true
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}

try {
  (Get-Content pubspec.yaml -Raw) -replace '(?m)^  store: true', '  store: false' |
    Set-Content pubspec.yaml -NoNewline
  fvm dart run msix:create --build-windows false --install-certificate false `
    --certificate-path $pfx --certificate-password $password `
    --output-name synctogether-dev --output-path $outDir
  if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }
} finally {
  # Not a rewrite of the original text: Set-Content would leave a BOM behind.
  git checkout -- pubspec.yaml
}

$subjectSigned = (Get-AuthenticodeSignature $msix).SignerCertificate.Subject
if ($subjectSigned -ne $subject) { throw "MSIX signed as '$subjectSigned', expected '$subject'" }
Write-Host "Built $msix" -ForegroundColor Green

if (-not $NoInstall) {
  # An update cannot replace files a running copy holds open (0x80073D02).
  $installed = Get-AppxPackage SinghSoftwareServices.SyncTogether
  if ($installed) {
    # By install folder, not just name: helper processes also pin the package.
    Get-Process -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -and $_.Path.StartsWith($installed.InstallLocation, 'OrdinalIgnoreCase') } |
      Stop-Process -Force
  }
  Get-Process synctogether -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  try {
    Add-AppxPackage $msix -ForceUpdateFromAnyVersion
  } catch {
    # Last resort: drop the old install (and its local data, e.g. the signed-in
    # session) and install clean.
    Write-Host "Update failed ($(($_.Exception.Message -split '\r?\n')[0].Trim())); reinstalling clean." -ForegroundColor Yellow
    Get-AppxPackage SinghSoftwareServices.SyncTogether | Remove-AppxPackage
    Add-AppxPackage $msix
  }
  Write-Host 'Installed.' -ForegroundColor Green
}
