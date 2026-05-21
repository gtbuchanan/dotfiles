# Invoked by wt's post_create / post_checkout / post_pr hooks to bring a
# new worktree up to a usable state. Add more bootstrap steps below as
# needed (mise install, uv sync, etc.).

function Copy-FromMain([string]$rel) {
  $dst = Join-Path $env:WT_PATH $rel
  New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $env:WT_MAIN $rel) -Destination $dst
}

# Mirror untracked per-checkout files from $WT_MAIN, preserving subdirs:
#   *.local      .env.local, .cleanignore.local
#   *.local.*    .env.local.json, mise.local.toml
#   *.user       *.csproj.user, *.vbproj.user, *.fsproj.user
# `--directory` collapses ignored dirs (node_modules, dist, .venv, ...) into
# one entry that the regex discards cheaply (the trailing `/` fails `[^/]*$`).
& git -C $env:WT_MAIN ls-files --others --exclude-standard --ignored --directory 2>$null |
  Where-Object { $_ -match '\.(local|user)(\.[^/]*)?$' } |
  ForEach-Object { Copy-FromMain $_ }

# Carry over Visual Studio per-solution user state from .vs/:
#   - applicationhost.config: IIS Express bindings that .local files reference
#   - <ver>/.suo: startup project, window layout, breakpoints
# Skip the rest of .vs/ (IntelliSense caches, browse DBs) — VS regenerates.
'.vs/*/config/applicationhost.config', '.vs/*/v*/.suo' |
  ForEach-Object { Join-Path $env:WT_MAIN $_ } |
  Get-ChildItem -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-FromMain ([IO.Path]::GetRelativePath($env:WT_MAIN, $_.FullName)) }

if (Test-Path "$env:WT_PATH/pnpm-lock.yaml") {
  pnpm -C $env:WT_PATH install --frozen-lockfile
}
