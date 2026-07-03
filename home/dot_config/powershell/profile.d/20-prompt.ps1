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

# Enable Starship
Invoke-Expression (&starship init powershell)

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
