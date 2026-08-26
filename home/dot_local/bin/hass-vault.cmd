@echo off
rem Entry point for the mise [env] exec() calls in home-assistant.toml, which
rem name a bare command that has to resolve from PATH on every platform. A .ps1
rem isn't executable, so this shim exists only to reach the PowerShell script
rem beside it under the same name Termux's resolver uses. See hass-vault.ps1.
rem
rem -NoProfile keeps profile output off stdout, which mise captures verbatim as
rem the credential -- and avoids re-entering the profile from inside an [env]
rem evaluation that the profile's own `mise activate` triggered.
pwsh -NoLogo -NoProfile -File "%~dp0hass-vault.ps1" %*
