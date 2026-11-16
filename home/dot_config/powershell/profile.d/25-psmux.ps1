# Deletes the layout psmux-snapshot saved once the last pane's own shell exits
# by hand, so the next server boot restores nothing: closing every pane is a
# choice to start over. PowerShell.Exiting fires for `exit` but not when psmux
# kills the shell (kill-pane, kill-server, the server dying in a reboot), and
# those leave the layout for psmux-restore to rebuild.
#
# psmux's own hooks cannot do this. `pane-exited` fires for the last pane, but
# the server exits before the `run-shell` it starts can finish, and psmux ends
# a namespace's last session even with `exit-empty off`. The shell's exit
# handler runs while the pane still exists, so psmux still lists it.
#
# Three checks keep it from deleting a layout that should survive:
# - Only the pane's own shell counts, its pid psmux's `#{pane_pid}`. A pwsh
#   started inside the pane loads this profile too, and exiting it leaves the
#   pane open.
# - Only the last pane counts, across every session on the server.
# - Only a layout this server saved counts. psmux-snapshot writes one file for
#   whichever server it ran in, and a throwaway `-L` server exiting must not
#   take the default server's layout with it.

function Clear-PsmuxLayoutOnExit {
  if (-not $env:TMUX) { return }

  $layout = Join-Path $HOME '.psmux/layout.json'
  if (-not (Test-Path -LiteralPath $layout)) { return }

  # $TMUX is <socket>,<server pid>,<session id>, and the socket's leaf names
  # the server. `-L default` reaches a different socket than the unnamed
  # default server, which only a bare invocation reaches (see psmux-snapshot).
  $namespace = (($env:TMUX -split ',')[0] -split '[/\\]')[-1]
  $server = if ($namespace -eq 'default') { @() } else { @('-L', $namespace) }

  $panePids = @(psmux @server list-panes -a -F '#{pane_pid}' 2>$null)
  if ($panePids.Count -ne 1 -or $panePids[0] -ne "$PID") { return }

  $saved = try {
    (Get-Content -LiteralPath $layout -Raw | ConvertFrom-Json).namespace
  }
  catch { return }
  if (($saved ?? 'default') -ne $namespace) { return }

  Remove-Item -LiteralPath $layout -Force -ErrorAction SilentlyContinue
}

if ($env:TMUX) {
  $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Clear-PsmuxLayoutOnExit
  }
}
