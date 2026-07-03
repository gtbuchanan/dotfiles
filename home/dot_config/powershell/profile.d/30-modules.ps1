# Must load after 20-prompt: that part's `Set-PSReadLineOption -EditMode Vi`
# resets the PSReadLine keymap, which would clobber the PSFzf Tab rebind below
# if it ran first. The profile.d numeric prefixes keep this in order.

# Configure PowerShellGet
Import-Module PowerShellGet

# Configure PSFzf
Import-Module PSFzf
Set-PSReadLineKeyHandler `
  -Key Tab `
  -BriefDescription 'Fzf Tab Completion' `
  -Description 'Autocomplete commands via fzf' `
  -ScriptBlock { Invoke-FzfTabCompletion }
function local:Write-AtCursor ([Parameter(ValueFromPipeline)]$Result) {
  if ($Result.Length -gt 0) {
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($Result -join "")
  }
  [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
# Define simpler chords than `GitKeyBindings`
Set-PSReadLineKeyHandler -Chord 'Ctrl+g,b' -ScriptBlock {
  Invoke-PsFzfGitBranches | Write-AtCursor
}
Set-PSReadLineKeyHandler -Chord 'Ctrl+g,f' -ScriptBlock {
  Invoke-PsFzfGitFiles | Write-AtCursor
}
# PSFzf tries Ctrl+g,Ctrl+h for this, but it doesn't actually work (likely due to PSReadLine)
Set-PSReadLineKeyHandler -Chord 'Ctrl+g,h' -ScriptBlock {
  Invoke-PsFzfGitHashes | Write-AtCursor
}
Set-PSReadLineKeyHandler -Chord 'Ctrl+g,s' -ScriptBlock {
  Invoke-PsFzfGitStashes | Write-AtCursor
}
Set-PSReadLineKeyHandler -Chord 'Ctrl+g,t' -ScriptBlock {
  Invoke-PsFzfGitTags | Write-AtCursor
}
Set-PsFzfOption `
  -PSReadlineChordProvider 'Ctrl+t' `
  -PSReadlineChordReverseHistory 'Ctrl+r' `
  -PSReadlineChordReverseHistoryArgs 'Alt+a' `
  -PSReadlineChordSetLocation 'Alt+c'

# Configure posh-git
Import-Module posh-git
