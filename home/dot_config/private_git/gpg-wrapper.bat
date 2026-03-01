@echo off
set "GPG_PATH=C:\Program Files\GnuPG\bin\gpg.exe"
if not defined GPG_TTY goto :run
if defined CLAUDE_CODE goto :run
if defined AI_AGENT goto :run
"%GPG_PATH%" --pinentry-mode loopback %*
goto :EOF
:run
"%GPG_PATH%" %*
