# Configure aliases
Set-Alias -Name c -Value clear
Set-Alias -Name cm -Value chezmoi
Set-Alias -Name g -Value git
Set-Alias -Name pn -Value pnpm
{{- if eq .hosttype "ewn" }}
Set-Alias -Name tg -Value TortoiseGitProc
{{- end }}

Function cmcd { cd (cm source-path) }

# Configure Oh My Posh
$env:POSH_THEME = "$env:POSH_THEMES_PATH/cobalt2.omp.json"
oh-my-posh init pwsh | Invoke-Expression

# Configure posh-git
Import-Module posh-git

{{- if eq .hosttype "ewn" }}
# Configure PSRSA module
Import-Module -Name $env:USERPROFILE/Code/PSRSA/src/PSRSA.psm1

# Configure JIRA CLI
$env:JIRA_API_TOKEN = {{ (index (dashlanePassword "JIRA API Token") 0).password | quote }}
{{- end }}
