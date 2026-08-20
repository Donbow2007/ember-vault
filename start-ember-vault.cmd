@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-ember-vault.ps1" %*
exit /b %ERRORLEVEL%
