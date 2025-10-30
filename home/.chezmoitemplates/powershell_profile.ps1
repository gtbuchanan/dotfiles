# Configure aliases
Set-Alias -Name c -Value clear
Set-Alias -Name cm -Value chezmoi
Set-Alias -Name cmm -value chezmoi_modify_manager
Set-Alias -Name g -Value git
Set-Alias -Name htop -Value ntop
Set-Alias -Name pn -Value pnpm
{{- if and (eq .hosttype "ewn") (eq .chezmoi.os "windows") }}
Set-Alias -Name tg -Value TortoiseGitProc
{{- end }}
Set-Alias -Name top -Value ntop
Set-Alias -Name v -Value vim

$ChezmoiSourcePath = Join-Path "{{ .chezmoi.sourceDir }}" ".."

Function cmcd { Set-Location $ChezmoiSourcePath }

# Sane ls formatting
Remove-Alias ls -ErrorAction SilentlyContinue
{{- if eq .chezmoi.os "windows" }}
Function ls {
  $NewArgs = New-Object System.Collections.Generic.List[object]
  foreach ($Arg in $Args) {
    $Uri = $null
    $Arg = $Arg.Replace("~", $env:USERPROFILE)
    if ([Uri]::TryCreate($Arg, [UriKind]::RelativeOrAbsolute, [ref]$Uri) -and $Uri.Scheme -eq "file") {
      $Arg = $(wsl wslpath $Arg.Replace("\", "/"))
    }
    $NewArgs.Add($Arg)
  }
  $NewArgs = $NewArgs.Count -gt 0 ? $NewArgs -join " " : "."
  wsl ls --color=auto -hF $NewArgs
}

Function su { sudo pwsh -NoLogo }

Function Update-SessionEnvironment {
  # Adapted from StackOverflow:
  # https://stackoverflow.com/a/31845512/1409101
  $env:Path = `
    [System.Environment]::GetEnvironmentVariable("Path", "Machine") + `
    ";" + `
    [System.Environment]::GetEnvironmentVariable("Path", "User")
}

Function refreshenv { Update-SessionEnvironment }
{{- end }}

# Configure OSC 7 for Starship
# https://wezterm.org/shell-integration.html#osc-7-on-windows-with-powershell-with-starship
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

# Configure PowerShellGet
Import-Module PowerShellGet

# Configure posh-git
Import-Module posh-git

{{- if and (eq .hosttype "ewn") (eq .chezmoi.os "windows") }}
# Configure PSRSA module
Import-Module -Name $env:USERPROFILE/Code/PSRSA/src/PSRSA.psm1

# Configure JIRA CLI
$env:JIRA_API_TOKEN = {{ (index (dashlanePassword "JIRA API Token") 0).password | quote }}
{{- end }}
