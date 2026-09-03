$ErrorActionPreference = 'Stop'

# Materialize the tools pinned in the global mise config. Deploying a conf.d
# fragment only writes the pin -- nothing installs it, so a tool resolved during
# shell startup would be missing until something happened to call its shim, and
# the shell that needed it is the one that would go without.
#
# Run from $HOME so only the global config is in scope. Inside a project, this
# would pull that project's whole toolchain on every apply.
#
# Converging rather than change-triggered: run_onchange_ would fire on the pins
# it rendered, and the tools also go missing for reasons no pin records -- a
# pruned install directory, a version removed by hand, a machine restored from a
# backup that skipped them.
if (Get-Command mise -CommandType Application -ErrorAction SilentlyContinue) {
  mise -C $HOME install
}
