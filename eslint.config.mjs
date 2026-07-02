import { configure } from '@gtbuchanan/eslint-config';

const config = await configure({ tsconfigRootDir: import.meta.dirname });

export default [
  ...config,
  {
    // chezmoi templates only look like JSON/TOML (they embed {{ }}); modify_
    // scripts aren't the file type their suffix implies; CLAUDE.md is a
    // one-line @AGENTS.md import pointer, not prose.
    ignores: ['**/modify_*', 'CLAUDE.md', 'home/.chezmoitemplates/**'],
  },
];
