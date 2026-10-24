# Pushes metadata/msstore_listing_en-US.json (description, features, What's New...)
# onto the Microsoft Store draft submission for a product, then commits the draft.
#
#   pwsh tool/apply_msstore_listing.ps1 -ProductId 9P1BZTSXHDFS [-NoCommit]
#
# `msstore publish <msix>` uploads a package and never touches listing text, so
# without this the Store keeps whatever the last hand edit left there. Run it
# against a draft (`msstore publish --noCommit` makes one) - a submission in
# PreProcessing/Certification is locked against metadata edits.
param(
  [Parameter(Mandatory)] [string] $ProductId,
  [string] $ListingPath = '',
  [string] $Locale = 'en-us',
  [switch] $NoCommit
)
$ErrorActionPreference = 'Stop'
if (-not $ListingPath) {
  $ListingPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '../metadata/msstore_listing_en-US.json'
}

$listing = Get-Content -Raw -Encoding utf8 $ListingPath | ConvertFrom-Json

$raw = (msstore submission get $ProductId) -join "`n"
$start = $raw.IndexOf('{')
if ($start -lt 0) { throw "msstore returned no submission JSON:`n$raw" }
$draft = $raw.Substring($start) | ConvertFrom-Json

$base = $draft.Listings.$Locale.BaseListing
if (-not $base) { throw "Draft has no '$Locale' listing." }

# Images carry Partner Center file ids, so they stay as the draft has them.
foreach ($key in 'Keywords', 'Description', 'Features', 'ReleaseNotes', 'Title',
                 'ShortTitle', 'ShortDescription', 'LicenseTerms',
                 'CopyrightAndTrademarkInfo', 'DevStudio') {
  $base.$key = $listing.$key
}

$payload = Join-Path ([IO.Path]::GetTempPath()) "msstore_submission_$ProductId.json"
[IO.File]::WriteAllText($payload, ($draft | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))

msstore submission updateMetadata $ProductId -p $payload
if ($LASTEXITCODE -ne 0) { throw "updateMetadata failed ($LASTEXITCODE)" }

if ($NoCommit) { Write-Host 'Draft updated; not committed (-NoCommit).'; return }
msstore submission publish $ProductId
if ($LASTEXITCODE -ne 0) { throw "submission publish failed ($LASTEXITCODE)" }
