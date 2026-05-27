# Invoked by wt's post_remove hook to clean up branch state after the
# worktree directory is gone. Mirrors `wt-cleanup` on POSIX — see that
# script for the strategy comments.

& git -C $env:WT_MAIN branch -d $env:WT_BRANCH 2>$null
if ($LASTEXITCODE -eq 0) { exit 0 }

$track = & git -C $env:WT_MAIN for-each-ref `
  --format='%(upstream:track)' "refs/heads/$env:WT_BRANCH" 2>$null
if ($track -eq '[gone]') {
  & git -C $env:WT_MAIN branch -D $env:WT_BRANCH
  exit 0
}

& git -C $env:WT_MAIN branch -d $env:WT_BRANCH
exit 0
