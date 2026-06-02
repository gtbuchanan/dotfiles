# Load modular profile parts from profile.d in numeric-prefix order.
# Use the foreach STATEMENT (not ForEach-Object) so dot-sourcing lands
# aliases/functions in the profile's scope, not a pipeline child scope.
$profileD = Join-Path $PSScriptRoot "profile.d"
foreach ($part in Get-ChildItem $profileD -Filter "*.ps1" | Sort-Object Name) {
  . $part.FullName
}
