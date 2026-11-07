import { configure } from '@gtbuchanan/eslint-config';

const config = await configure({ tsconfigRootDir: import.meta.dirname });

export default [
  ...config,
  {
    // .mise/locks holds the dependency graphs `mise lock` generates for npm:
    // tools, whose package.json pins would trip the catalog rule; chezmoi
    // templates only look like JSON/TOML (they embed {{ }}); modify_ scripts
    // aren't the file type their suffix implies; CLAUDE.md is a one-line
    // @AGENTS.md import pointer, not prose.
    ignores: [
      '**/modify_*',
      '.mise/locks/**',
      'CLAUDE.md',
      'home/.chezmoitemplates/**',
    ],
  },
];
