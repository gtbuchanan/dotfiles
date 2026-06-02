# Windows auto-loads only Documents/PowerShell; the canonical profile lives in
# ~/.config/powershell (shared with Linux/macOS). Dot-source it.
. (Join-Path $HOME ".config/powershell/Microsoft.PowerShell_profile.ps1")
