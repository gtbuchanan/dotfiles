# SOPS Age Identity

The age identity that decrypts SOPS-encrypted secrets lives in the Bitwarden
vault rather than in `~/.config/sops/age/keys.txt`. sops reads it through
`SOPS_AGE_KEY_CMD`, which names a helper that fetches it on each run, so the key
exists in memory for one sops invocation and never on disk. Wired up on
**Termux, personal hosts**.

## SOPS File Map

| File                                                                                          | Role                                                                                  |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [`home/dot_claude/deny-unsafe-commands`](../home/dot_claude/deny-unsafe-commands)             | Refuses an agent running the helper's `identity` command                              |
| [`home/dot_local/bin/.chezmoiignore`](../home/dot_local/bin/.chezmoiignore)                   | Deploys the helper on personal Termux hosts only                                      |
| [`home/dot_local/bin/executable_sops-age-key`](../home/dot_local/bin/executable_sops-age-key) | The helper: session from `bw-session-termux`, key from `bw`                           |
| [`home/dot_local/lib/bw-vault-termux.sh`](../home/dot_local/lib/bw-vault-termux.sh)           | Vault access shared with `hass-vault`: session, scoped `bw`, sync before every search |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                           | Exports `SOPS_AGE_KEY_CMD`, under the same gate                                       |
| [`test/sops_age_key_test.sh`](../test/sops_age_key_test.sh)                                   | shUnit2 suite, every CI leg (`mise run test:shunit2`)                                 |

## SOPS Vault Item Format

A secure note named `SOPS/AGE Key` whose notes hold `keys.txt` verbatim, as
`age-keygen` writes it. The helper prints only the `AGE-SECRET-KEY-1` lines.
`SOPS_AGE_KEY_ITEM` searches another name.

The search is loose, so the helper narrows its hits to items whose notes carry
an identity and refuses to guess between two that do.

## SOPS Session Scope

The helper takes the session from `bw-session-termux` and hands it to `bw` in
its own process. Exporting `BW_SESSION` with `bwu` would work as well and give
up the point: every child of that shell, agent sessions included, could then
read the vault without a prompt.

So each resolve costs a fingerprint. sops loads identities once for each age
master key it tries, so a file with several age recipients can ask more than
once.

The fingerprint is a tripwire, not a boundary. The hardware key carries no
per-use authentication (`termux-keystore generate` without `-u`), so code
running as this user can derive the KEK and skip the dialog. It makes an agent
decrypting through sops visible; keeping agents out of the operator's uid is
what would stop one.

## Diagnosing a Failed SOPS Decrypt

sops captures the helper's stderr and reports only an exit status, so the
reason never reaches the terminal. Run `sops-age-key check`: it resolves the
same way and reports how many identities it found, without printing one.

Never run `sops-age-key` bare to test it. `identity` is the default command, and
it prints the key.

## Retiring keys.txt

sops reads `keys.txt` alongside `SOPS_AGE_KEY_CMD` when both exist, so the file
keeps working, and keeps the key on disk, until it is deleted. Confirm
`sops-age-key check` resolves before removing it.
