import { configure } from '@gtbuchanan/eslint-config';

const config = await configure({ tsconfigRootDir: import.meta.dirname });

export default [
  ...config,
  {
    // chezmoi templates only look like JSON/TOML (they embed {{ }}); modify_
    // scripts aren't the file type their suffix implies.
    ignores: ['home/.chezmoitemplates/**', '**/modify_*'],
  },
];
