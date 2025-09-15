# Configure aliases
Set-Alias -Name c -Value clear
Set-Alias -Name cm -Value chezmoi
Set-Alias -Name cmm -value chezmoi_modify_manager
Set-Alias -Name g -Value git
Set-Alias -Name pn -Value pnpm
{{- if and (eq .hosttype "ewn") (eq .chezmoi.os "windows") }}
Set-Alias -Name tg -Value TortoiseGitProc
{{- end }}

Function cmcd { cd "$(cm source-path)/.." }

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
{{- end }}

# Configure Oh My Posh
$env:POSH_THEME = (Join-Path "$env:POSH_THEMES_PATH" "cobalt2.omp.json")
oh-my-posh init pwsh --config $env:POSH_THEME | Invoke-Expression

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
