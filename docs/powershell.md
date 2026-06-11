# PowerShell Profile

PowerShell is the primary shell on Windows and is installed on Linux and macOS
too. Rather than keep a per-OS copy of the profile, this repo maintains a single
canonical profile split into ordered parts, and points each OS's PowerShell at
it. Android is the only target without PowerShell, so the profile is excluded
there.

## File Map

| File | Role |
|---|---|
| [`home/.chezmoiignore`](../home/.chezmoiignore) | Excludes `.config/powershell` on Android |
| [`home/dot_config/powershell/.chezmoiignore`](../home/dot_config/powershell/.chezmoiignore) | Gates `50-ewn.ps1` to ewn+Windows |
| [`home/dot_config/powershell/Microsoft.PowerShell_profile.ps1`](../home/dot_config/powershell/Microsoft.PowerShell_profile.ps1) | Loader: dot-sources `profile.d/*.ps1` in order |
| [`home/dot_config/powershell/profile.d/00-aliases.ps1.tmpl`](../home/dot_config/powershell/profile.d/00-aliases.ps1.tmpl) | `Set-Alias`/`Remove-Alias` (+ `tg` on ewn+Windows) |
| [`home/dot_config/powershell/profile.d/10-functions.ps1.tmpl`](../home/dot_config/powershell/profile.d/10-functions.ps1.tmpl) | `ccc`, `cmcd`, and Windows-only `ls`/`su`/`refreshenv` |
| [`home/dot_config/powershell/profile.d/20-prompt.ps1`](../home/dot_config/powershell/profile.d/20-prompt.ps1) | Starship init + OSC 7, PSReadLine vi-mode |
| [`home/dot_config/powershell/profile.d/30-modules.ps1`](../home/dot_config/powershell/profile.d/30-modules.ps1) | PowerShellGet, PSFzf + keybindings, posh-git |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl) | `GPG_TTY`, mise activation, worktrunk shell init, delta completion |
| [`home/dot_config/powershell/profile.d/50-ewn.ps1.tmpl`](../home/dot_config/powershell/profile.d/50-ewn.ps1.tmpl) | PSRSA + Cloudflare token (ewn+Windows only) |
| [`home/readonly_Documents/PowerShell/Microsoft.PowerShell_profile.ps1`](../home/readonly_Documents/PowerShell/Microsoft.PowerShell_profile.ps1) | Windows stub: dot-sources the `~/.config` profile |

## Canonical Location and the Windows Stub

PowerShell auto-loads a different profile path per OS:
`~/.config/powershell/Microsoft.PowerShell_profile.ps1` on Linux/macOS, but
`~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` on Windows. To keep a
single source of truth, the real profile lives at `~/.config/powershell` on
**every** OS; only PowerShell's auto-load logic is Windows-specific. On Windows,
the `Documents/PowerShell` profile is a one-line stub that dot-sources the
`~/.config/powershell` profile.

## Cross-References

- `GPG_TTY` wiring: see [`gpg-signing.md`](gpg-signing.md).
- worktrunk shell integration: see [`worktrunk.md`](worktrunk.md).
- The Starship prompt itself is configured in
  [`home/dot_config/private_starship.toml`](../home/dot_config/private_starship.toml); `20-prompt` only initializes it.
