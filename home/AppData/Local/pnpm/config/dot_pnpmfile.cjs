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
function readPackage(pkg) {
  if (pkg.name === 'volar-service-emmet' && pkg.dependencies?.['@emmetio/css-parser']) {
    pkg.dependencies['@emmetio/css-parser'] = '^0.4.1';
  }
  return pkg;
}

module.exports = { hooks: { readPackage } };
