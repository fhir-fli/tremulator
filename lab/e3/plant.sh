#!/usr/bin/env bash
# E3: runs a command in a throwaway copy of the code with one defect planted.
#
#     bash lab/e3/plant.sh NAME COMMAND...        (NAME = plants/NAME.patch)
#     bash lab/e3/plant.sh none COMMAND...        (the same copy, nothing planted)
#
# The copy is a git worktree of HEAD beside this repository (the packages
# reach sibling repositories by relative path, so it must sit at the same
# depth). The patch must apply cleanly, and `git diff --stat` of the copy is
# printed, so a plant that changed nothing cannot pass for one. COMMAND runs
# from the copy's root; its exit code is this script's. The copy is removed.
set -euo pipefail
name=$1; shift
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
wt="$(dirname "$REPO")/tremulator-e3-$name"
[ ! -e "$wt" ] || { echo "plant.sh: $wt exists; remove it first" >&2; exit 1; }
git -C "$REPO" worktree add --detach -q "$wt" HEAD
trap 'git -C "$REPO" worktree remove --force "$wt"' EXIT
if [ "$name" != none ]; then
  git -C "$wt" apply --whitespace=nowarn "$HERE/plants/$name.patch"
  changed=$(git -C "$wt" diff --stat)
  [ -n "$changed" ] || { echo "plant.sh: $name changed nothing" >&2; exit 1; }
  echo "planted $name:"; echo "$changed"
fi
code=0
(cd "$wt" && "$@") || code=$?
echo "plant.sh $name: exit $code"
exit "$code"
