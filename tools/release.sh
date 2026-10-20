#!/bin/sh
# Prepare and push a release tag with the right Zenodo metadata in the tree.
#
# The GitHub–Zenodo integration reads .zenodo.json from the TAGGED tree and
# groups every release of this repo under one Zenodo concept, so the file
# must describe the package being released. This script swaps it from the
# per-package templates in .zenodo/ before tagging.
#
# Usage: tools/release.sh misocialr|misocialpy X.Y.Z
# Then publish the GitHub release (which triggers Zenodo):
#   gh release create <tag> --title "<pkg> X.Y.Z" --notes "..."

set -e

pkg=$1
ver=$2
[ -n "$pkg" ] && [ -n "$ver" ] || { echo "usage: tools/release.sh misocialr|misocialpy X.Y.Z" >&2; exit 2; }

case "$pkg" in
  misocialr)  tag="v$ver" ;;
  misocialpy) tag="misocialpy-v$ver" ;;
  *) echo "unknown package: $pkg" >&2; exit 2 ;;
esac

cd "$(git rev-parse --show-toplevel)"
[ -f ".zenodo/$pkg.json" ] || { echo "missing .zenodo/$pkg.json" >&2; exit 1; }

cp ".zenodo/$pkg.json" .zenodo.json
if ! git diff --quiet -- .zenodo.json; then
  git add .zenodo.json
  git commit -m "release: Zenodo metadata for $pkg $ver"
fi

git tag "$tag"
git push origin main "$tag"
echo "Tagged $tag. Now: gh release create $tag --title \"$pkg $ver\" --notes \"...\""
