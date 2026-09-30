$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$env:EMBER_VAULT_DATA_DIR = if ($env:EMBER_VAULT_DATA_DIR) { $env:EMBER_VAULT_DATA_DIR } else { Join-Path $Root "storage" }
$env:EMBER_VAULT_PORTABLE = "1"
$env:EMBER_VAULT_BUNDLED_RUNTIME = "1"
$env:GEM_HOME = Join-Path $Root "vendor\bundle"
$env:GEM_PATH = $env:GEM_HOME
$env:LLAMA_SERVER_PATH = Join-Path $Root "runtime\llama\llama-server.exe"
Set-Location $Root
& (Join-Path $Root "runtime\ruby\bin\ruby.exe") "bin/ember-vault" start
Start-Process "http://localhost:$($(if ($env:PORT) { $env:PORT } else { '3000' }))"
