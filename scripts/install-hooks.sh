#!/bin/sh
# Opt-in installer for this repo's local git hooks. Never run automatically
# -- a developer runs this once, by choice (see CONTRIBUTING.md). Idempotent:
# safe to re-run any time (e.g. after pulling a hook update).
#
# Currently installs:
#   pre-push -> scripts/check-finding-tracking.sh (advisory finding-ID/
#               .ssd/features/ tracking check; see that script's header)
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
hooks_dir="$repo_root/.git/hooks"

if [ ! -d "$hooks_dir" ]; then
  echo "install-hooks: $hooks_dir not found -- not a git checkout?" >&2
  exit 1
fi

pre_push="$hooks_dir/pre-push"
marker='# Installed by scripts/install-hooks.sh'

if [ -e "$pre_push" ] && ! grep -qF "$marker" "$pre_push" 2>/dev/null; then
  if [ "${1:-}" != "--force" ]; then
    echo "install-hooks: $pre_push already exists and wasn't installed by this" >&2
    echo "  script -- refusing to overwrite it. Back it up or remove it, or" >&2
    echo "  re-run with --force to overwrite anyway." >&2
    exit 1
  fi
  echo "install-hooks: --force given, overwriting existing $pre_push" >&2
fi

# Git's pre-push protocol: for each ref being pushed, one line on stdin,
# "<local ref> <local sha1> <remote ref> <remote sha1>". A local sha1 of
# all zeros means a delete (nothing pushed, nothing to check); a remote
# sha1 of all zeros means a new ref (no upstream commit to diff against,
# so fall back to the single tip commit).
cat > "$pre_push" <<'HOOK'
#!/bin/sh
# Installed by scripts/install-hooks.sh -- do not edit by hand, re-run that
# script instead. Advisory only: never blocks a push (see
# scripts/check-finding-tracking.sh for what this checks and why).
set -eu

repo_root=$(git rev-parse --show-toplevel)
zero='0000000000000000000000000000000000000000'

while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$zero" ] && continue   # delete, nothing pushed
  if [ "$remote_sha" = "$zero" ]; then
    # New ref, no remote history to diff against directly -- use where it
    # branched from main instead, so this checks the branch's own new
    # commits, not the entire reachable history.
    base=$(git merge-base main "$local_sha" 2>/dev/null) || continue
    range="$base..$local_sha"
  else
    range="$remote_sha..$local_sha"
  fi
  "$repo_root/scripts/check-finding-tracking.sh" "$range" || true
done

exit 0
HOOK

chmod +x "$pre_push"
echo "install-hooks: installed $pre_push"
