# Free Ctrl+Space for terminal apps (e.g. the psmux/tmux C-Space prefix) by
# removing the Windows IME hotkeys bound to it. The Text Services Framework
# registers Ctrl+Space (VK_SPACE 0x20 + MOD_CONTROL 0x02) as an "IME on/off"
# toggle under HKCU\Control Panel\Input Method\Hot Keys - by default, even
# with only a US English layout - and ctfmon swallows the key before it
# reaches the focused app. Removing those subkeys lets Ctrl+Space through.
#
# Idempotent: only removes hotkeys whose binding is exactly Ctrl+Space
# (Ctrl-only modifier), leaving Shift+Space and punctuation-mode hotkeys.
$HotKeys = 'HKCU:\Control Panel\Input Method\Hot Keys'
if (Test-Path $HotKeys) {
  Get-ChildItem $HotKeys | Where-Object {
    $props = Get-ItemProperty $_.PSPath
    $vk = $props.'Virtual Key'
    $mod = $props.'Key Modifiers'
    # VK_SPACE with Ctrl-only (low modifier byte 0x02; excludes Shift/Alt).
    $vk -and $mod -and $vk[0] -eq 0x20 -and $mod[0] -eq 0x02
  } | ForEach-Object {
    Remove-Item $_.PSPath -Recurse -Force -Confirm:$false
  }
}
