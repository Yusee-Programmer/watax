#!/bin/bash
set -e

# Push benchmark results with automatic conflict resolution
# If the remote has changed, merge using "ours" strategy (keep our benchmark results)

echo "=== Configuring Git ==="
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

echo "=== Staging benchmark results ==="
git add benchmarks/results.md

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "No benchmark changes to commit."
    exit 0
fi

echo "=== Creating commit ==="
git commit -m "ci: update watax benchmark results [skip ci]"

echo "=== Fetching latest remote changes ==="
git fetch origin main

echo "=== Merging remote changes (keeping our benchmark results) ==="
# Use -X ours to automatically resolve conflicts by keeping our version
if git merge --no-ff -X ours -m "Merge remote changes (keep our benchmark results)" origin/main; then
    echo "Merge successful, pushing to remote..."
else
    echo "Merge had conflicts, accepting our version..."
    # In case -X ours doesn't fully resolve, manually accept our version
    git checkout --ours benchmarks/results.md
    git add benchmarks/results.md
    git commit -m "Merge remote changes (keep our benchmark results)"
fi

echo "=== Pushing to remote ==="
git push origin main

echo "=== Push successful ==="
