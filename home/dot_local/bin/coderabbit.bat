@echo off
REM CodeRabbit CLI doesn't detect git worktrees (.git file vs directory).
REM Resolve via Windows git and pass to WSL with WSLENV path translation.
setlocal
for /f "delims=" %%a in ('git rev-parse --show-toplevel 2^>nul') do set "GIT_WORK_TREE=%%a"
for /f "delims=" %%a in ('git rev-parse --git-dir 2^>nul') do set "GIT_DIR=%%a"
set "WSLENV=GIT_DIR/p:GIT_WORK_TREE/p"
wsl ~/.local/bin/coderabbit %*
exit /b %ERRORLEVEL%
