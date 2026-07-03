@{
  # PowerShell Gallery modules the dev toolchain provisions into a repo-local,
  # gitignored .psmodules via scripts/provision-psmodules.ps1 (run from the mise
  # postinstall hook). Add a module by listing its pinned version here; the
  # provisioner is generic and installs whatever this manifest declares.
  #
  # Renovate keeps these current via the nuget datasource pointed at the
  # PowerShell Gallery feed (a custom manager in .github/renovate.json), so a
  # bump lands like any other dependency PR. Keep the mapping alphabetical to
  # reduce merge conflicts.
  PSScriptAnalyzer = '1.24.0'
}
