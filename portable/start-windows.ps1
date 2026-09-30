$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$env:EMBER_VAULT_DATA_DIR = if ($env:EMBER_VAULT_DATA_DIR) { $env:EMBER_VAULT_DATA_DIR } else { Join-Path $Root "storage" }
$env:EMBER_VAULT_PORTABLE = "1"
Set-Location $Root
ruby "bin/ember-vault" start
Start-Process "http://localhost:$($(if ($env:PORT) { $env:PORT } else { '3000' }))"
