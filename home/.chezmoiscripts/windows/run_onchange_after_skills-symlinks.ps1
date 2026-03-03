# skills-symlinks hash: 1
# Create directory symlinks so AI tools discover shared skills
$SkillsTarget = Join-Path $env:USERPROFILE ".config" "skills"
$Links = @(
    Join-Path $env:USERPROFILE ".claude" "skills"
    Join-Path $env:USERPROFILE ".copilot" "skills"
    Join-Path $env:USERPROFILE ".agents" "skills"
)
foreach ($Link in $Links) {
    if (Test-Path $Link) { Remove-Item $Link -Force }
    New-Item -ItemType SymbolicLink -Path $Link -Target $SkillsTarget | Out-Null
}
