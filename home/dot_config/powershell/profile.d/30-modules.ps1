# Must load after 20-prompt: that part's `Set-PSReadLineOption -EditMode Vi`
# resets the PSReadLine keymap, which would clobber the PSFzf Tab rebind below
# if it ran first. The profile.d numeric prefixes keep this in order.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSReviewUnusedParameter', 'wordToComplete',
  Justification = 'Completer arguments bind positionally, so this one must be declared'
)]
param()

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

# Configure posh-git lazily. Only its git tab completion is wanted here --
# starship renders the git prompt -- and that completion is registered as an
# import side effect rather than an exported command, so PowerShell's module
# auto-loading can never trigger it from `git <Tab>`. This stub does the import
# on the first completion and delegates; that import registers posh-git's own
# completer over this one, so the stub serves a single call per session and the
# import cost is paid only by sessions that complete a git command.
#
# `g` is named explicitly because posh-git discovers aliases pointing at git
# when it loads, which a stub registered before it cannot. See 00-aliases.
$gitCompleter = {
  param($wordToComplete, $commandAst, $cursorPosition)

  Import-Module posh-git

  # Pad the text back out to the cursor. Completion strips the trailing space,
  # and Expand-GitCommand needs it to tell `git checkout ` (offer refs) from
  # `git checkout` (still completing the subcommand).
  $padLength = $cursorPosition - $commandAst.Extent.StartOffset
  Expand-GitCommand $commandAst.ToString().PadRight($padLength, ' ').Substring(0, $padLength)
}
Microsoft.PowerShell.Core\Register-ArgumentCompleter `
  -Native `
  -CommandName git, gitk, tgit, g `
  -ScriptBlock $gitCompleter
