#!/bin/sh
# test/checks/branch-name.sh  -  enforce the branch naming convention.
#
# README.md requires every branch to be feature/<name> or fix/<name>, and
# .githooks/pre-push enforces it - but only for contributors who have run
#
#   git config core.hooksPath .githooks
#
# which git does not do on clone, and which the README notes is a manual step.
# So the rule is currently advisory for anyone who skipped it. Running the same
# rule in CI makes it apply to everyone.
#
# Branch is taken from, in order: the first argument, GITHUB_HEAD_REF (set on
# pull_request events to the SOURCE branch), GITHUB_REF_NAME (set on push), or
# the current local branch.
#
# Usage:
#   sh test/checks/branch-name.sh              # current branch
#   sh test/checks/branch-name.sh feature/foo  # explicit
#
# Exit code 0 = acceptable, 1 = does not match the convention.

set -u

branch="${1:-}"
[ -z "$branch" ] && branch="${GITHUB_HEAD_REF:-}"
[ -z "$branch" ] && branch="${GITHUB_REF_NAME:-}"
[ -z "$branch" ] && branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"

if [ -z "$branch" ]; then
    echo "branch-name: could not determine a branch name (detached HEAD?)"
    echo "             pass one explicitly: sh test/checks/branch-name.sh <branch>"
    exit 1
fi

case "$branch" in
    feature/?*|fix/?*|master)
        echo "branch-name: ok ($branch)"
        exit 0
        ;;
    feature/|fix/)
        echo "branch-name: '$branch' has an empty description after the prefix"
        exit 1
        ;;
    *)
        echo "branch-name: '$branch' does not match the convention"
        echo "             use feature/<short-description> or fix/<short-description>"
        echo "             see README.md > Contributing > Branch naming"
        exit 1
        ;;
esac
