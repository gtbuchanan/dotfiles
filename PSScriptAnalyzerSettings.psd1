@{
  # Auto-discovered by the VS Code PowerShell extension, so the editor and the
  # psscriptanalyzer hk step enforce the same rules. The step fails on any
  # finding (all severities), so no Severity gate is set. Default correctness
  # rules run regardless (IncludeDefaultRules only matters with CustomRulePath);
  # the entries below opt into the formatting rules, which are off by default.
  Rules = @{
    PSAvoidLongLines = @{
      Enable = $true
      MaximumLineLength = 100
    }
    PSAvoidSemicolonsAsLineTerminators = @{ Enable = $true }
    PSPlaceCloseBrace = @{
      Enable = $true
      NoEmptyLineBefore = $true
    }
    PSPlaceOpenBrace = @{ Enable = $true }
    PSUseConsistentIndentation = @{
      Enable = $true
      IndentationSize = 2
    }
    PSUseConsistentWhitespace = @{
      Enable = $true
      CheckParameter = $true
    }
    PSUseCorrectCasing = @{ Enable = $true }
  }
}
