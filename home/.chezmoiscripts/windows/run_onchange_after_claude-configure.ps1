$ErrorActionPreference = 'Stop'

$HttpServers = @{
  'microsoft-learn' = 'https://learn.microsoft.com/api/mcp'
}

foreach ($Name in $HttpServers.Keys) {
  claude mcp remove $Name --scope user 2>$null
  claude mcp add --scope user --transport http $Name $HttpServers[$Name]
}

# Install CodeRabbit plugin (review CLI runs in WSL via ~/.local/bin/coderabbit.bat shim)
claude plugin install coderabbit 2>$null
