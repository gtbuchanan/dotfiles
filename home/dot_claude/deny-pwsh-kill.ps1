# PreToolUse guard: block any Bash/PowerShell command that terminates
# PowerShell processes *by name or image* (e.g. `Stop-Process -Name pwsh`,
# `Get-Process pwsh | Stop-Process`, `taskkill /IM pwsh.exe`,
# `... | Invoke-CimMethod Terminate`, `(Get-Process pwsh).Kill()`). Those kills
# are session-blind -- with the persistent-host PowerShell tool they take down
# pwsh instances owned by *other* Claude Code sessions and the user's own
# terminals, not just this session's children.
#
# PID-targeted kills (`Stop-Process -Id <pid>`, `taskkill /PID <pid>`) do not
# name a PowerShell process, so they pass -- Claude can still reap a specific
# background job it started. Known residual gaps (a name-blind regex can't
# close these): a tree/PID kill that never names pwsh, and a false positive
# on a command that merely mentions both a kill token and "pwsh". A deny is
# recoverable, so we err toward blocking.
#
# Emits a PreToolUse `deny` decision on match; stays silent (exit 0) otherwise
# so normal permission handling continues.

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try {
  $payload = $raw | ConvertFrom-Json
}
catch {
  exit 0
}

$command = $payload.tool_input.command
if (-not $command) { exit 0 }

# Process-termination paths: Stop-Process (+ alias spps), the kill alias,
# taskkill, the .Kill() method, and WMI/CIM Terminate.
$killVerb = $command -match '(?i)(\b(Stop-Process|spps|kill|taskkill|Terminate)\b|\.Kill\s*\()'
# A PowerShell process referenced by name/image rather than a numeric PID.
$targetsPwsh = $command -match '(?i)pwsh|powershell'

if ($killVerb -and $targetsPwsh) {
  $reason = @(
    'Blocked: this command terminates PowerShell processes by name, which'
    'kills pwsh sessions in other Claude Code sessions and the user''s'
    'terminals. If you must stop a background job you started, target its'
    'PID explicitly with `Stop-Process -Id <pid>` instead.'
  ) -join ' '
  $decision = @{
    hookSpecificOutput = @{
      hookEventName = 'PreToolUse'
      permissionDecision = 'deny'
      permissionDecisionReason = $reason
    }
  }
  $decision | ConvertTo-Json -Depth 5 -Compress
}

exit 0
