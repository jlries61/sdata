#!/bin/sh
# Local pre-push advisory: warns when a commit being pushed cites an audit
# finding ID (the "(PA-1)", "(PB-5..8)"-shaped tags this project's commit
# messages use, e.g. commit 10b31d2) with no matching coverage under
# .ssd/features/ or .ssd/current.yml -- the SSD tracking artifacts this
# repo's CLAUDE.md treats as the record of what shipped. See:
#   .ssd/milestones/2026-09-03-post-pe-audit-remediation/skeptic-before.md
#   (Wirfs-Brock finding: current.yml's record-keeping responsibility is
#   unstated and unenforced -- this script is the enforcement half of that
#   finding's "narrow the responsibility, or enforce it" recommendation).
#
# Advisory only -- never blocks the push. .ssd/features/ can legitimately
# lag a commit by hours (the brief lands slightly after or alongside the
# code, not always before), and this repo's own SSD doctrine
# (methodology/core.md) treats gates as loud warnings, not walls. Install
# via scripts/install-hooks.sh; never auto-installed.
#
# A finding ID counts as tracked if it appears as a substring anywhere
# under .ssd/features/ OR in .ssd/current.yml -- NOT requiring a dedicated
# features/ directory per ID. Both locations matter: a full-SSD-rail
# workstream lives under .ssd/features/<slug>/, but this repo also tracks
# many small/doc-only fixes as a current.yml archived entry with no
# features/ directory at all (confirmed: pe1-3/pe5/pe6, "no full SSD rail"
# by their own text) -- checking only features/ would false-positive on
# every one of those. One workstream also commonly bundles many IDs in one
# place (e.g. this milestone's own pa-pb-pc6-backfill-2026-08-13-audit
# current.yml entry covers 17 IDs, not 17 directories).
#
# Usage: scripts/check-finding-tracking.sh [<range>]
#   <range>  git revision range to scan commit messages over, e.g.
#            "abc123..def456". The installed pre-push hook (see
#            install-hooks.sh) always passes this explicitly, computed from
#            git's pre-push stdin protocol (old-sha..new-sha per ref). Run
#            manually with no argument, defaults to HEAD~1..HEAD.
set -eu

cd "$(dirname "$0")/.."   # repo root

range=${1:-}

if [ -z "$range" ]; then
  if git rev-parse --verify -q HEAD~1 >/dev/null 2>&1; then
    range='HEAD~1..HEAD'
  else
    # First commit on the branch -- nothing to diff against.
    exit 0
  fi
fi

messages=$(git log --format='%B' "$range" 2>/dev/null) || {
  echo "check-finding-tracking: warning: could not read commit range '$range' -- skipping" >&2
  exit 0
}

[ -z "$messages" ] && exit 0

# Extract finding IDs like PA-1, PB-5, PB-5..8 (the ..N range form some
# commit messages use for a contiguous block, e.g. "(PA-2, PB-5..8)").
# Individual IDs only, one per line, deduplicated.
ids=$(printf '%s' "$messages" | grep -oE '\(P[A-Z]-[0-9]+(\.\.[0-9]+)?[^)]*\)' | \
      tr ',' '\n' | grep -oE 'P[A-Z]-[0-9]+(\.\.[0-9]+)?' | sort -u) || true

[ -z "$ids" ] && exit 0

if [ ! -d .ssd/features ] && [ ! -f .ssd/current.yml ]; then
  echo "check-finding-tracking: warning: neither .ssd/features/ nor .ssd/current.yml" \
       "exists -- cannot check finding-ID tracking for:" \
       "$(printf '%s' "$ids" | tr '\n' ' ')" >&2
  exit 0
fi

is_tracked() {
  # $1 = finding ID substring to search for.
  { [ -d .ssd/features ] && grep -rlq -- "$1" .ssd/features/ 2>/dev/null; } || \
  { [ -f .ssd/current.yml ] && grep -lq -- "$1" .ssd/current.yml 2>/dev/null; }
}

untracked=""
for id in $ids; do
  # Expand a "PB-5..8" range form into its individual member IDs before
  # checking coverage, since a tracking entry may cite the range form,
  # a single member, or the whole set individually.
  case "$id" in
    *..*)
      prefix=${id%-*}
      lo=${id#*-}; lo=${lo%%.*}
      hi=${id##*..}
      members=""
      n=$lo
      while [ "$n" -le "$hi" ]; do
        members="$members ${prefix}-${n}"
        n=$((n + 1))
      done
      ;;
    *) members=" $id" ;;
  esac

  for m in $members; do
    if ! is_tracked "$m"; then
      untracked="$untracked $m"
    fi
  done
done

if [ -n "$untracked" ]; then
  echo "check-finding-tracking: WARNING -- finding ID(s) cited in this push have no" >&2
  echo "  coverage under .ssd/features/ or .ssd/current.yml:$untracked" >&2
  echo "  Advisory only, not blocking. If this work has no brief yet, that's normal" >&2
  echo "  SSD sequencing -- but if it never gets one, current.yml silently drifts from" >&2
  echo "  what shipped (see the 2026-09-03 milestone's feynman C13 finding)." >&2
fi

exit 0
