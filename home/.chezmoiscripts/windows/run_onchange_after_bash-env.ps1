# Point BASH_ENV at ~/.config/bash_env, which every non-interactive bash sources
# before it runs anything. That file puts the native OpenSSH client ahead of the
# MSYS build Git Bash ships; see docs/ssh.md for what it fixes and why no other
# hook reaches those shells.
#
# User scope rather than machine: the file it names lives in this user's home,
# so a machine-wide value would hand every other account a path belonging to
# someone else. The DSC Environment resource the winget manifest uses for
# GIT_SSH cannot express that -- its Target accepts Machine and Process only --
# so the variable is set here instead, which also lands it in the same
# `chezmoi apply` that deploys the file.
#
# $HOME rather than a rendered path, so this script's content stays identical on
# every host and its run_onchange hash tracks what the script does.
#
# Already-running processes keep the environment they started with, so a shell
# or editor open across this apply still resolves the MSYS client until it is
# restarted.
$BashEnv = Join-Path $HOME '.config\bash_env'
if ([Environment]::GetEnvironmentVariable('BASH_ENV', 'User') -ne $BashEnv) {
  [Environment]::SetEnvironmentVariable('BASH_ENV', $BashEnv, 'User')
}
