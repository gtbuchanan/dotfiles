# Cache for tool-generated shell-init scripts.
#
# mise, starship, wt and delta each emit a static init script that the profile
# evaluates at startup. The scripts change only when the tool itself does, so
# re-deriving them per shell spends a process spawn on output already known.
# This caches each one against the binary's identity on disk.
#
# Must load before the parts that use it -- the profile.d numeric prefixes keep
# this in order.

# Keyed on path, size and mtime rather than `<tool> --version`, because asking
# the tool its version is the same spawn the cache exists to avoid. mise-managed
# tools also live in a version-stamped directory, so an upgrade moves the path
# and misses the cache regardless.
function Get-InitCacheKey ([string] $BinaryPath) {
  $item = Get-Item -LiteralPath $BinaryPath -Force -ErrorAction Stop
  # Resolve links before reading size and mtime. winget publishes mise as a
  # symlink under Links\, and such a link reports length 0 with an mtime that
  # tracks the link rather than the binary -- so keyed on the link, an upgrade
  # would leave the entry pinned to the old init script indefinitely.
  if ($item.ResolvedTarget -and $item.ResolvedTarget -ne $item.FullName) {
    $item = Get-Item -LiteralPath $item.ResolvedTarget -Force -ErrorAction Stop
  }
  '{0}|{1}|{2}' -f $item.FullName, $item.LastWriteTimeUtc.Ticks, $item.Length
}

function Get-InitCacheDirectory {
  $root = if ($IsWindows) {
    $env:LOCALAPPDATA
  }
  else {
    if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME '.cache' }
  }
  Join-Path $root 'powershell/init-cache'
}

function Get-CachedInitScript {
  param(
    [Parameter(Mandatory)][string] $Name,
    [Parameter(Mandatory)][string] $BinaryPath,
    [Parameter(Mandatory)][scriptblock] $Generate,
    [string] $CacheDirectory = (Get-InitCacheDirectory)
  )

  # Every failure below falls through to $Generate. A cache that cannot be read
  # or written costs a spawn; one that throws costs the caller its init script,
  # which is the tool not working at all.
  try {
    $key = Get-InitCacheKey $BinaryPath
    $path = Join-Path $CacheDirectory $Name
  }
  catch {
    Write-Debug "init cache: no key for $Name -- $($_.Exception.Message)"
    return & $Generate
  }

  try {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
      # Split on the first newline only: the payload is a script whose own
      # blank and trailing lines have to survive intact, which -split and
      # Get-Content's line mode would not preserve.
      $break = $content.IndexOf("`n")
      if ($break -ge 0 -and $content.Substring(0, $break) -ceq $key) {
        return $content.Substring($break + 1)
      }
    }
  }
  catch {
    Write-Debug "init cache: unreadable entry for $Name -- $($_.Exception.Message)"
    return & $Generate
  }

  $initScript = & $Generate

  try {
    if (-not (Test-Path -LiteralPath $CacheDirectory -PathType Container)) {
      New-Item -ItemType Directory -Path $CacheDirectory -Force -ErrorAction Stop | Out-Null
    }
    # Write then move, so a shell starting while another writes reads either
    # the old entry or the new one rather than a half-written file.
    $temp = Join-Path $CacheDirectory "$Name.$PID.tmp"
    $body = "$key`n$initScript"
    Set-Content -LiteralPath $temp -Value $body -NoNewline -Encoding utf8 -ErrorAction Stop
    Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop
  }
  catch {
    # Cached nothing; the caller still gets its script.
    Write-Debug "init cache: could not store $Name -- $($_.Exception.Message)"
  }

  $initScript
}
