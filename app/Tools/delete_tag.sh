#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: mise run delete-tag -- vMAJOR.MINOR.PATCH, for example v0.1.0" >&2
    exit 2
fi

tag="$1"
remote_tag="refs/tags/$tag"

git remote get-url origin >/dev/null

if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is required to verify whether $tag has an associated release." >&2
    exit 1
fi

if ! repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
    echo "Could not determine the GitHub repository from origin." >&2
    exit 1
fi

release_error="$(mktemp)"
if gh release view "$tag" --repo "$repo" --json tagName >/dev/null 2>"$release_error"; then
    rm -f "$release_error"
    echo "Tag $tag has an associated GitHub Release and will not be deleted." >&2
    exit 1
fi

if ! grep -Eqi 'release (not found|not exist)|not found|404' "$release_error"; then
    cat "$release_error" >&2
    rm -f "$release_error"
    echo "Could not verify whether $tag has an associated GitHub Release." >&2
    exit 1
fi
rm -f "$release_error"

remote_exists=false
if git ls-remote --exit-code --tags origin "$remote_tag" >/dev/null 2>&1; then
    remote_exists=true
fi

local_exists=false
if git show-ref --verify --quiet "$remote_tag"; then
    local_exists=true
fi

if [[ "$remote_exists" == true && "$local_exists" == false ]]; then
    git fetch origin "$remote_tag:$remote_tag"
    local_exists=true
fi

if [[ "$remote_exists" == false && "$local_exists" == false ]]; then
    echo "Tag $tag does not exist locally or on origin." >&2
    exit 1
fi

if [[ "$remote_exists" == true ]]; then
    if ! git push origin ":$remote_tag"; then
        echo "Remote deletion failed; local tag $tag was preserved." >&2
        exit 1
    fi
    echo "Deleted $tag from origin."
fi

if [[ "$local_exists" == true ]]; then
    git tag -d "$tag"
fi
