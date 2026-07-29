/* Patch volar-service-emmet@0.0.64's git-resolved @emmetio/css-parser to the
 * npm-published version. pnpm 11's blockExoticSubdeps rejects the github fork,
 * and overrides/packageExtensions aren't honored in the global config.
 *
 * The fix shipped in volar-service-emmet 0.0.67+, but @vue/language-server 2.x
 * pins 0.0.64 exactly with no v2 backport tracked upstream
 * (https://github.com/volarjs/services/issues/112). We're stuck on v2 because
 * v3 requires the LSP client to forward tsserver/request messages to vtsls,
 * which Claude Code doesn't implement
 * (https://github.com/Piebald-AI/claude-code-lsps/issues/43).
 */

/** @param {import('@pnpm/types').PackageManifest} pkg */
function readPackage(pkg) {
  if (pkg.name === 'volar-service-emmet' && pkg.dependencies?.['@emmetio/css-parser']) {
    return {
      ...pkg,
      dependencies: { ...pkg.dependencies, '@emmetio/css-parser': '^0.4.1' },
    };
  }
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
  if (pkg.name === 'ink-link' && !pkg.dependencies?.react) {
    return { ...pkg, dependencies: { ...pkg.dependencies, react: '^19' } };
  }
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
  if (
    pkg.name === '@azure/monitor-opentelemetry-exporter' &&
    !pkg.dependencies?.['@azure/logger']
  ) {
    return {
      ...pkg,
      dependencies: { ...pkg.dependencies, '@azure/logger': '^1' },
    };
  }
  return pkg;
}

module.exports = { hooks: { readPackage } };
