$ErrorActionPreference = 'Stop'

$HttpServers = @{
  'microsoft-learn' = 'https://learn.microsoft.com/api/mcp'
}

foreach ($Name in $HttpServers.Keys) {
  claude mcp remove $Name --scope user 2>$null
  claude mcp add --scope user --transport http $Name $HttpServers[$Name]
}

# Install LSP language servers
pnpm install -g @vtsls/language-server @vue/language-server@2 vscode-langservers-extracted 2>$null
if (-not (Get-Module -ListAvailable PowerShellEditorServices)) {
  $Zip = Join-Path $env:TEMP 'PowerShellEditorServices.zip'
  $Dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Modules'
  gh release download --repo PowerShell/PowerShellEditorServices --pattern 'PowerShellEditorServices.zip' --dir $env:TEMP --clobber 2>$null
  Expand-Archive -Path $Zip -DestinationPath $Dest -Force
}

# Install plugins (marketplace add is idempotent)
claude plugin marketplace add Piebald-AI/claude-code-lsps 2>$null
claude plugin install coderabbit 2>$null
claude plugin install vtsls@claude-code-lsps 2>$null
claude plugin install vue-volar@claude-code-lsps 2>$null
# claude plugin install vscode-langservers@claude-code-lsps 2>$null
claude plugin install powershell-editor-services@claude-code-lsps 2>$null

# Patch LSP plugin configs for Windows
# See: https://github.com/anthropics/claude-code/issues/16751
$PluginDirs = @(
  Join-Path $env:USERPROFILE '.claude/plugins/cache/claude-code-lsps'
  Join-Path $env:USERPROFILE '.claude/plugins/marketplaces/claude-code-lsps'
)

# Append .cmd to npm shim commands so shell:true can resolve them
$CmdShims = @('vtsls', 'vscode-html-language-server', 'vscode-css-language-server', 'vscode-eslint-language-server')
foreach ($dir in $PluginDirs) {
  Get-ChildItem -Path $dir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.lsp\.json|marketplace\.json' } | ForEach-Object {
    $json = Get-Content $_.FullName -Raw
    foreach ($shim in $CmdShims) {
      $json = $json -replace "`"command`":\s*`"$shim`"", "`"command`": `"$shim.cmd`""
    }
    Set-Content -Path $_.FullName -Value $json -NoNewline
  }
}

# PSES: fix Unix paths and suppress session file in cwd
foreach ($dir in $PluginDirs) {
  $PsesConfig = Get-ChildItem -Path $dir -Filter '.lsp.json' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*powershell-editor-services*' }
  foreach ($cfg in $PsesConfig) {
    $json = Get-Content $cfg.FullName -Raw
    $json = $json -replace "-LogPath '/dev/null'", "-LogPath ([System.IO.Path]::Combine(`$env:TEMP, 'pses.log'))"
    $json = $json -replace "-LogLevel 'None'", "-LogLevel 'None' -SessionDetailsPath ([System.IO.Path]::Combine(`$env:TEMP, 'pses-session.json'))"
    Set-Content -Path $cfg.FullName -Value $json -NoNewline
  }
}

# Patch Claude Code: LSP diagnostics + conditional shell:true for .cmd shims
pnpm dlx tweakcc --restore 2>$null
pnpm dlx tweakcc --apply --patches "fix-lsp-support" 2>$null
$PatchScript = @'
js = js.replace(
  /(\w+)\.spawn\((\w+),(\w+),\{(stdio:\["pipe","pipe","pipe"\],env:\{[^}]+\},cwd:\w+\?\.cwd,windowsHide:!0)\}\)/,
  (m, mod, cmd, args, opts) =>
    `${mod}.spawn(${cmd},${args},{${opts},shell:/\\.cmd$/i.test(${cmd})})`
);
return js;
'@
$PatchFile = Join-Path $env:TEMP 'fix-lsp-spawn.js'
Set-Content -Path $PatchFile -Value $PatchScript -NoNewline
'y' | pnpm dlx tweakcc adhoc-patch --script "@$PatchFile" 2>$null
