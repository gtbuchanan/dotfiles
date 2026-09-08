# Configure OSC 7 for Starship
# https://wezterm.org/shell-integration.html#osc-7-on-windows-with-powershell-with-starship
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingInvokeExpression', '',
  Justification = 'starship init emits a script string to Invoke-Expression'
)]
param()

$prompt = ""
function Invoke-Starship-PreCommand {
  $current_location = $executionContext.SessionState.Path.CurrentLocation
  if ($current_location.Provider.Name -eq "FileSystem") {
    $ansi_escape = [char]27
    $provider_path = $current_location.ProviderPath -replace "\\", "/"
    $prompt = "$ansi_escape]7;file://${env:COMPUTERNAME}/${provider_path}$ansi_escape\"
  }
  $host.ui.Write($prompt)
}

# Enable Starship. `--print-full-init` emits the whole init script directly;
# the documented `starship init powershell` instead emits a stub that shells
# out to starship a second time, so this spawns one process at startup rather
# than two. See https://github.com/starship/starship/issues/1032.
# The full init spans multiple lines, which the shell captures as an array, so
# join it back into one string for Invoke-Expression.
#
# Resolved to a single command because the wrappers directory and mise's shims
# dir both carry a starship, and the cache keys on the binary behind the name.
$starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($starship) {
  # Guarded because a present-but-failing binary yields an empty script, which
  # Invoke-Expression rejects outright rather than treating as a no-op.
  $starshipInit = Get-CachedInitScript -Name 'starship' -BinaryPath $starship.Source -Generate {
    (@(& $starship init powershell --print-full-init) -join "`n")
  }
  if ($starshipInit) {
    $starshipInit | Invoke-Expression
  }
}

# Enable Vi mode
$env:VI_MODE_PROMPT = "I "
Set-PSReadLineOption -EditMode Vi -ViModeIndicator Script -ViModeChangeHandler {
  switch ($args[0]) {
    'Command' { $env:VI_MODE_PROMPT = "N " }
    'Insert' { $env:VI_MODE_PROMPT = "I " }
    'Visual' { $env:VI_MODE_PROMPT = "V " }
    default { $env:VI_MODE_PROMPT = "??" }
  }
  [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
