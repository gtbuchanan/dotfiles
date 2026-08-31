/* Deliberately NOT named .pnpmfile.cjs. pnpm auto-discovers that name in the
 * workspace root and stamps a `pnpmfileChecksum` into pnpm-lock.yaml, but
 * Renovate regenerates lockfiles with --ignore-pnpmfile and drops the key —
 * so every lockfile-touching Renovate PR failed CI's `pnpm install
 * --frozen-lockfile` with ERR_PNPM_LOCKFILE_CONFIG_MISMATCH. Nothing here
 * applies to the workspace's own dependencies: every patch below targets a
 * package installed by `pnpm add -g`, which reaches this file through the
 * explicit --config.global-pnpmfile in home/.chezmoitemplates/pnpm-globals.
 * Renaming it back would reintroduce the CI failure.
 *
 * Dependency fixups for globals whose published manifests don't survive
 * pnpm's isolated node_modules. Each entry pins one dependency onto one
 * package; `when` says whether the fixup applies to a dep the manifest
 * already declares ('declared', to repoint it) or omits ('missing', to add
 * it). Adding a case is a new entry here, never a new branch below.
 *
 * @type {ReadonlyArray<{
 *   package: string,
 *   dependency: string,
 *   spec: string,
 *   when: 'declared' | 'missing',
 * }>}
 */
const patches = [
  /* @azure/monitor-opentelemetry-exporter (the applicationinsights telemetry
   * pulled by @pnp/cli-microsoft365) requires @azure/logger in its compiled
   * output but declares it as neither a dependency nor a peerDependency — it
   * relies on @azure/logger being hoisted (it's a transitive dep of the many
   * @azure/core-* packages, all of which depend on it). Under our hoist: false
   * workspace it isn't linked into the exporter's scope, so the CLI crashes at
   * load with "Cannot find module '@azure/logger'". Hoisted layouts (npm) mask
   * the bug. Add @azure/logger as an explicit dep so pnpm symlinks the
   * already-resolved copy into the exporter's scope.
   *
   * A recurring Azure SDK anti-pattern (@azure/logger left in devDependencies
   * while used in dist): https://github.com/Azure/azure-sdk-for-js/issues/26618
   * (@azure/cosmos), https://github.com/Azure/azure-sdk-for-js/issues/9477
   * (@azure/identity). No exporter-specific issue is filed yet.
   *
   * Drop this patch once the exporter declares @azure/logger as a dependency.
   */
  {
    package: '@azure/monitor-opentelemetry-exporter',
    dependency: '@azure/logger',
    spec: '^1',
    when: 'missing',
  },
  /* @bitwarden/cli's webpack bundle requires the `buffer` shim (note the
   * trailing slash in `require("buffer/")` — not the node builtin) without
   * declaring it; npm's hoisted layout supplies it, so upstream never notices.
   *
   * Latent for us until pnpm 11 started symlinking global packages into the
   * store link farm (`store/v11/links/...`). Node resolves to realpath before
   * walking node_modules, so the search now starts inside the store and never
   * reaches the global dir's hoisted `.pnpm/node_modules`, where buffer sits.
   * `bw` then dies at startup with "Cannot find module 'buffer/'".
   *
   * Only Buffer.from(...).toString(...) is used — identical in buffer 5 and 6.
   * No upstream issue is filed. Drop this patch once the CLI declares buffer.
   */
  {
    package: '@bitwarden/cli',
    dependency: 'buffer',
    spec: '^6',
    when: 'missing',
  },
  /* ink-link@4.1.0 imports react in its compiled output but declares it
   * neither as a dependency nor a peerDependency (only `ink` is a peer). Under
   * pnpm's isolated node_modules, react isn't linked into ink-link's scope, so
   * ESM resolution fails ("Cannot find package 'react'") and tweakcc — which
   * pulls ink-link — crashes on startup. Hoisted layouts (npm) mask the bug.
   * Add react as an explicit dep so pnpm symlinks the already-resolved
   * react@19 into ink-link's scope.
   *
   * ink-link@5.0.0 still omits react (deps: terminal-link, peer: ink).
   * Reported upstream: https://github.com/sindresorhus/ink-link/issues/21
   * Drop this patch once ink-link declares react.
   */
  { package: 'ink-link', dependency: 'react', spec: '^19', when: 'missing' },
  /* Patch volar-service-emmet@0.0.64's git-resolved @emmetio/css-parser to the
   * npm-published version. pnpm 11's blockExoticSubdeps rejects the github
   * fork, and overrides/packageExtensions aren't honored in the global config.
   *
   * The fix shipped in volar-service-emmet 0.0.67+, but @vue/language-server
   * 2.x pins 0.0.64 exactly with no v2 backport tracked upstream
   * (https://github.com/volarjs/services/issues/112). We're stuck on v2
   * because v3 requires the LSP client to forward tsserver/request messages to
   * vtsls, which Claude Code doesn't implement
   * (https://github.com/Piebald-AI/claude-code-lsps/issues/43).
   */
  {
    package: 'volar-service-emmet',
    dependency: '@emmetio/css-parser',
    spec: '^0.4.1',
    when: 'declared',
  },
];

/**
@param {import('@pnpm/types').PackageManifest} pkg
*/
function readPackage(pkg) {
  const patch = patches.find(
    candidate =>
      candidate.package === pkg.name &&
      (candidate.when === 'declared') ===
      Object.hasOwn(pkg.dependencies ?? {}, candidate.dependency),
  );
  return patch
    ? {
        ...pkg,
        dependencies: { ...pkg.dependencies, [patch.dependency]: patch.spec },
      }
    : pkg;
}

module.exports = { hooks: { readPackage } };
