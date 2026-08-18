$ErrorActionPreference = "Stop"

$RepositoryUrl = if ($env:EMBER_VAULT_REPOSITORY) { $env:EMBER_VAULT_REPOSITORY } else { "https://github.com/Donbow2007/ember-vault.git" }
$InstallRoot = if ($env:EMBER_VAULT_INSTALL_ROOT) { $env:EMBER_VAULT_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "EmberVault" }
$AppRoot = Join-Path $InstallRoot "app"
$DataRoot = Join-Path $InstallRoot "data"

function Ensure-WingetPackage($Id) {
  winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "Windows Package Manager (winget) is required. Install App Installer from Microsoft, then run this script again."
}

Ensure-WingetPackage "Git.Git"
Ensure-WingetPackage "RubyInstallerTeam.RubyWithDevKit.3.3"
Ensure-WingetPackage "OpenJS.NodeJS.LTS"
Ensure-WingetPackage "oschwartz10612.Poppler"

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
New-Item -ItemType Directory -Force -Path $InstallRoot, $DataRoot | Out-Null

if (Test-Path (Join-Path $AppRoot ".git")) {
  git -C $AppRoot fetch origin main
  git -C $AppRoot merge --ff-only origin/main
} else {
  git clone --branch main $RepositoryUrl $AppRoot
}

$StoragePath = Join-Path $AppRoot "storage"
$StorageItem = Get-Item $StoragePath -Force
if (-not ($StorageItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  Get-ChildItem $StoragePath -Force | Where-Object { $_.Name -ne ".keep" } | Move-Item -Destination $DataRoot
  Remove-Item (Join-Path $StoragePath ".keep") -Force -ErrorAction SilentlyContinue
  Remove-Item $StoragePath -Force
  cmd /c "mklink /J `"$StoragePath`" `"$DataRoot`"" | Out-Null
}

$env:EMBER_VAULT_DATA_DIR = $DataRoot
& (Join-Path $AppRoot "bin\ember-vault") setup

$LauncherPath = Join-Path $InstallRoot "start-ember-vault.ps1"
@"
`$env:EMBER_VAULT_DATA_DIR = "$DataRoot"
Set-Location "$AppRoot"
& ruby "bin\ember-vault" run
"@ | Set-Content -Encoding UTF8 $LauncherPath

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherPath`""
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)
Register-ScheduledTask -TaskName "Ember Vault" -Action $Action -Trigger $Trigger -Settings $Settings -Description "Ember Vault offline knowledge server" -Force | Out-Null
Start-ScheduledTask -TaskName "Ember Vault"

Write-Host "Ember Vault is installed. Open http://localhost:3000"
Write-Host "ZIM archives require a Windows zimdump binary on PATH; other documents, maps, and search work without it."
