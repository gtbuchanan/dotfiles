{{- if eq .chezmoi.os "windows" -}}
oh-my-posh init pwsh --config $env:POSH_THEMES_PATH/cobalt2.omp.json | Invoke-Expression

{{ end -}}
Set-Alias -Name c -Value clear
Set-Alias -Name cm -Value chezmoi
Set-Alias -Name g -Value git
Set-Alias -Name pn -Value pnpm

Function cmcd { cd (cm source-path) }
