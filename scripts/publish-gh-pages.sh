#!/usr/bin/env bash
#
# Publish gh-pages-staging/ to the gh-pages branch and push.
#
# Usage:
#   scripts/publish-gh-pages.sh                   # commit message: "Update landing page"
#   scripts/publish-gh-pages.sh "Tweak hero copy" # custom commit message
#
# What it does:
#   1. Verifies gh-pages-staging/ exists and is non-empty
#   2. Creates a throwaway worktree on the gh-pages branch at /tmp/<repo>-gh-pages
#   3. Mirrors gh-pages-staging/ → worktree (deletes any files no longer in staging)
#   4. Commits and pushes if there are changes; no-op if not
#   5. Tears the worktree down (always, even on failure)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STAGING="$REPO_ROOT/gh-pages-staging"
WORKTREE="/tmp/$(basename "$REPO_ROOT")-gh-pages"
MESSAGE="${1:-Update landing page}"

# --- sanity checks ------------------------------------------------------------
if [[ ! -d "$STAGING" ]]; then
  echo "error: $STAGING does not exist" >&2
  exit 1
fi
if [[ -z "$(ls -A "$STAGING" 2>/dev/null)" ]]; then
  echo "error: $STAGING is empty — nothing to publish" >&2
  exit 1
fi
if ! git show-ref --verify --quiet refs/heads/gh-pages && \
   ! git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  echo "error: gh-pages branch does not exist locally or on origin" >&2
  exit 1
fi

# --- always clean the worktree on exit ----------------------------------------
cleanup() {
  if [[ -d "$WORKTREE" ]]; then
    git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
  fi
}
trap cleanup EXIT

# --- spin up worktree ---------------------------------------------------------
# Pull the latest gh-pages so we don't push a stale base.
git fetch origin gh-pages >/dev/null 2>&1 || true
echo "==> Creating worktree at $WORKTREE on gh-pages"
git worktree add "$WORKTREE" gh-pages >/dev/null
cd "$WORKTREE"
git pull --ff-only origin gh-pages >/dev/null 2>&1 || true

# --- mirror staging → worktree ------------------------------------------------
# rsync with --delete makes the worktree match staging exactly, so a removed
# file in staging gets removed on gh-pages too. Excludes the .git pointer.
echo "==> Mirroring $STAGING → worktree"
rsync -a --delete --exclude='.git' "$STAGING/" ./

# --- commit + push ------------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  echo "==> No changes to publish"
  exit 0
fi

echo "==> Committing: $MESSAGE"
git commit -m "$MESSAGE" >/dev/null

echo "==> Pushing to origin/gh-pages"
git push origin gh-pages

echo "==> Done. Page will rebuild in ~30-60s: https://emiller6505.github.io/JamBox/"
