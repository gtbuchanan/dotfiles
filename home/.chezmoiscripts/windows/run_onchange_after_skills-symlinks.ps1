# Symlink ~/.claude/skills to the canonical ~/.agents/skills directory so
# Claude Code (which only reads ~/.claude/skills) sees the shared skills.
$SkillsTarget = Join-Path $env:USERPROFILE ".agents" "skills"
$Link = Join-Path $env:USERPROFILE ".claude" "skills"
if (Test-Path $Link) { Remove-Item $Link -Force }
New-Item -ItemType SymbolicLink -Path $Link -Target $SkillsTarget | Out-Null
