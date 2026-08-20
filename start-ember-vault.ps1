$ErrorActionPreference = "Stop"

$AppRoot = $PSScriptRoot
$DataRoot = if ($env:EMBER_VAULT_DATA_PATH) {
  $env:EMBER_VAULT_DATA_PATH
} elseif ($env:EMBER_VAULT_DATA_DIR) {
  $env:EMBER_VAULT_DATA_DIR
} else {
  Join-Path $AppRoot "data"
}
$Command = if ($args.Count -gt 0) { $args[0] } else { "run" }
$RemainingArguments = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

$env:EMBER_VAULT_DATA_PATH = $DataRoot
$env:EMBER_VAULT_DATA_DIR = $DataRoot
$env:EMBER_VAULT_PORTABLE = "1"
if (-not $env:BUNDLE_PATH) { $env:BUNDLE_PATH = Join-Path $AppRoot "vendor\bundle" }
if (-not $env:BIND_ADDRESS) { $env:BIND_ADDRESS = "127.0.0.1" }
if (-not $env:RAILS_MAX_THREADS) { $env:RAILS_MAX_THREADS = "2" }
if (-not $env:JOB_CONCURRENCY) { $env:JOB_CONCURRENCY = "1" }
if (-not $env:EMBER_VAULT_AI_THREADS) { $env:EMBER_VAULT_AI_THREADS = "2" }

Set-Location $AppRoot
if (-not (Get-Command ruby -ErrorAction SilentlyContinue) -or -not (Get-Command bundle -ErrorAction SilentlyContinue)) {
  throw "Ruby 3.3 and Bundler must be installed on this computer."
}

if ($Command -eq "setup") {
  if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js and npm are required during Setup for offline map indexing."
  }
  & bundle config set --local path $env:BUNDLE_PATH
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & ruby "bin\ember-vault" setup @RemainingArguments
  exit $LASTEXITCODE
}

& bundle check *> $null
if ($LASTEXITCODE -ne 0) {
  throw "This drive has not been prepared for this operating system and CPU. Run .\start-ember-vault.ps1 setup."
}

if (-not (Get-Command zimdump -ErrorAction SilentlyContinue)) {
  Write-Warning "zimdump is unavailable; existing content works, but new ZIM archives cannot be indexed."
}
if (-not (Get-Command pdftoppm -ErrorAction SilentlyContinue)) {
  Write-Warning "pdftoppm is unavailable; PDF text works, but page previews are unavailable."
}

& bundle exec ruby "bin\ember-vault" $Command @RemainingArguments
exit $LASTEXITCODE
