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
  return pkg;
}

module.exports = { hooks: { readPackage } };
