param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Target
)

$ErrorActionPreference = "Stop"
$RepositoryUrl = if ($env:EMBER_VAULT_REPOSITORY) { $env:EMBER_VAULT_REPOSITORY } else { "https://github.com/Donbow2007/ember-vault.git" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git must be installed for the initial portable installation."
}
if ((Test-Path $Target) -and (Get-ChildItem -Force $Target | Select-Object -First 1)) {
  throw "The destination already exists and is not empty: $Target"
}

$Parent = Split-Path -Parent $Target
if ($Parent) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
& git clone --branch main --single-branch $RepositoryUrl $Target
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Target "start-ember-vault.ps1") setup
exit $LASTEXITCODE
