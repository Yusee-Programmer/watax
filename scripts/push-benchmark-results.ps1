# Push benchmark results with automatic conflict resolution (Windows)
# If the remote has changed, merge using "ours" strategy (keep our benchmark results)

$ErrorActionPreference = "Stop"

Write-Output "=== Configuring Git ==="
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

Write-Output "=== Staging benchmark results ==="
git add benchmarks/results.md

Write-Output "=== Checking for changes ==="
$status = & git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Output "No benchmark changes to commit."
    exit 0
}

Write-Output "=== Creating commit ==="
git commit -m "ci: update watax benchmark results [skip ci]"

Write-Output "=== Fetching latest remote changes ==="
git fetch origin main

Write-Output "=== Merging remote changes (keeping our benchmark results) ==="
# Use -X ours to automatically resolve conflicts by keeping our version
$mergeOutput = & git merge --no-ff -X ours -m "Merge remote changes (keep our benchmark results)" origin/main 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output "Merge had conflicts, accepting our version..."
    # In case -X ours doesn't fully resolve, manually accept our version
    git checkout --ours benchmarks/results.md
    git add benchmarks/results.md
    git commit -m "Merge remote changes (keep our benchmark results)"
} else {
    Write-Output "Merge successful, pushing to remote..."
}

Write-Output "=== Pushing to remote ==="
git push origin main

Write-Output "=== Push successful ==="
