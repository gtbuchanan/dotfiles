@echo off
rem SSH_ASKPASS entry point. OpenSSH requires an executable, so this shim exists
rem only to reach the PowerShell script beside it. See ssh-askpass-bw.ps1.
rem
rem -NoProfile keeps the profile out of stdout, which OpenSSH reads as the
rem secret. %~1 rather than %* because the prompt is a single argument
rem containing spaces and an apostrophe.
pwsh -NoLogo -NoProfile -File "%~dp0ssh-askpass-bw.ps1" "%~1"
