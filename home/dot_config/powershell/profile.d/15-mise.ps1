# Must load before 20-prompt: that part runs `starship init`, which resolves
# the binary at load time. A mise-managed tool activated afterwards would have
# its init run against whatever copy the system supplies, and the pinned one
# would only take over for later interactive calls. The profile.d numeric
# prefixes keep this in order.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingInvokeExpression', '',
  Justification = 'mise activate emits a script string to Invoke-Expression'
)]
param()

# Activate mise (tool version + env + task manager); prepends real tool
# paths, overriding the shims dir that stays on the user PATH (added by the
# winget config on Windows) for non-interactive contexts
$mise = Get-Command mise -CommandType Application -ErrorAction SilentlyContinue
if ($mise) {
  # Placeholder so mise's own activation cleanup (Remove-Item function:mise)
  # has a target on first run; invoke the captured binary so this stub
  # doesn't shadow it. Prevents a benign but $Error-polluting path-not-found.
  function mise { }
  & $mise activate pwsh | Out-String | Invoke-Expression
}

# Re-prepend the wrapper directory, since activation puts mise's real tool paths
# in front of whatever the user PATH set. A wrapper is only reachable ahead of
# the tool it wraps, and mise-managed tools resolve to their install directory
# here, not the shim. See the winget config's wrappersPath resource.
$wrappers = Join-Path $HOME '.local\bin\wrappers'
if (Test-Path $wrappers) {
  $env:PATH = "$wrappers$([IO.Path]::PathSeparator)$env:PATH"
}
