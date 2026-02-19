@echo off
set "GPG_PATH=C:\Program Files\GnuPG\bin\gpg.exe"
if defined GPG_TTY (
  "%GPG_PATH%" --pinentry-mode loopback %*
) else (
  "%GPG_PATH%" %*
)
