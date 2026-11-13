# RDP

Remote desktop goes through the built-in `mstsc` client, driven by `.rdp`
connection files kept in the private host inventory beside the ssh
definitions. `rdp <host>` opens one, and tab completion lists the hosts the
inventory holds. The command deploys only where chezmoi's `hosttype` is
`personal` and the OS is Windows, the one combination with both `mstsc` and
the inventory clone.

## RDP File Map

| File                                                                                                                    | Role                                                     |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                 | Clones the private host inventory on personal hosts      |
| [`home/dot_config/powershell/profile.d/45-remote.ps1.tmpl`](../home/dot_config/powershell/profile.d/45-remote.ps1.tmpl) | `rdp` and its host-name completer                        |
| [`test/RdpCommand.Tests.ps1`](../test/RdpCommand.Tests.ps1)                                                             | Pester suite driving `rdp` against a sandboxed inventory |

## RDP Connection Files

The inventory, `gtbuchanan/hosts`, holds one file per host under
`rdp/<site>/<host>.rdp` (see
[Private SSH Host Inventory](ssh.md#private-ssh-host-inventory) for why it is a
separate private repo). `rdp` finds a file by its base name across every site,
so the command never needs to know the sites, and it refuses a name two sites
share rather than picking one. Arguments after the host pass through to
`mstsc`, so `rdp dc01 /f` opens fullscreen and `rdp dc01 /admin` takes the
admin session.

A file holds whatever `mstsc /edit` can save, which is every display,
redirection and gateway setting the client has. That is why the inventory
stores `.rdp` files rather than a data file rendered into them: the client
already defines the format, and a generator would only re-describe it.

## RDP Credentials

`mstsc` has no credential argument, and an `.rdp` file's `password 51` field is
a DPAPI blob only the machine that wrote it can decrypt, so it cannot travel in
a repo. Passwords live in Windows Credential Manager instead, under the target
`TERMSRV/<full address>`, stored once per machine:

```powershell
cmdkey /generic:TERMSRV/<full address> /user:<DOMAIN\user> /pass
```

A bare `/pass` prompts, keeping the password out of shell history. The target
must match the file's `full address` exactly, or `mstsc` falls back to
prompting.

## RDP File Security Prompt

Since the April 2026 security update (CVE-2026-26151), `mstsc` shows a
security dialog each time it opens an unsigned `.rdp` file, with every
redirection unticked and no way to dismiss it for good. `mstsc /v:<host>`
skips the dialog, but it accepts only the address and a few display flags, so
launching that way would discard the settings the files exist to carry. `rdp`
opens the files unsigned, and the prompt is the price.

Signing a temporary copy at launch would remove the prompt only if the
signature chains to a root the client trusts. A spike on 2026-11-13 found:

- `rdpsign` signs with a certificate in `Cert:\CurrentUser\My`, unelevated.
  Its `/sha256` option looks the certificate up by its SHA1 thumbprint despite
  the name, and given the SHA256 thumbprint it fails with `0x80092004`.
- The trusted .rdp publishers policy, `TrustedCertThumbprints` under
  `Software\Policies\Microsoft\Windows NT\Terminal Services`, takes the SHA256
  thumbprint with a `sha256:` prefix. Writing it needs elevation even in the
  user hive, and on a domain-joined host GPO already manages the `HKLM` key.
- A self-signed certificate listed in that policy still shows "Unknown
  publisher", so `mstsc` validates the chain before it consults the list.
  Trusting the certificate as a root was not tested.

Signing therefore needs a CA whose root every client already trusts, such as
an AD CS enterprise CA. Adding a self-signed root instead would trust it for
code signing across the account, so without such a CA the files stay unsigned.
