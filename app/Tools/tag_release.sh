#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: mise run tag-release -- vMAJOR.MINOR.PATCH, for example v0.1.0" >&2
    exit 2
fi

tag="$1"
git tag -a "$tag" -m "Argentic $tag"
if ! git push origin "refs/tags/$tag:refs/tags/$tag"; then
    echo "Push failed; local tag $tag still exists. Push it again or remove it before retrying." >&2
    exit 1
fi
