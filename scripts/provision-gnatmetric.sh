#!/bin/sh
# Locate or build gnatmetric (from the Alire libadalang_tools crate) and print
# its absolute path on stdout. Idempotent; called by `make complexity-check`
# and by CI. See doc/specs/2026-06-15-gnatmetric-ci-gate-design.md.
#
# Heavy on first run: building libadalang_tools pulls in libadalang from source.
# Subsequent runs reuse the built binary (and CI caches the tools/ directory).
#
# Note: `alr get` refuses to run inside an enclosing Alire crate, and the sdata
# repo root is one. So we fetch into a temp dir outside any crate, then relocate
# the fetched crate into TOOLS_DIR before building.
set -eu

LAL_TOOLS_VERSION=26.0.0
TOOLS_DIR=${TOOLS_DIR:-tools}

# 1. Already on PATH (e.g. a distro/AdaCore install)?
if command -v gnatmetric >/dev/null 2>&1; then
  command -v gnatmetric
  exit 0
fi

# 2. Previously built under TOOLS_DIR?
existing=$(ls "$TOOLS_DIR"/libadalang_tools_*/bin/gnatmetric 2>/dev/null | head -n1 || true)
if [ -n "${existing:-}" ] && [ -x "$existing" ]; then
  printf '%s/gnatmetric\n' "$(cd "$(dirname "$existing")" && pwd)"
  exit 0
fi

# 3. Fetch (outside any crate) and build it (heavy).
# alr writes progress to stdout; redirect it to stderr so this script's stdout
# carries ONLY the final gnatmetric path (the caller does GNATMETRIC=$(...)).
mkdir -p "$TOOLS_DIR"
abs_tools=$(cd "$TOOLS_DIR" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
( cd "$tmp" && alr -n -f get "libadalang_tools=$LAL_TOOLS_VERSION" ) >&2
fetched=$(ls -d "$tmp"/libadalang_tools_*/ 2>/dev/null | head -n1)
[ -n "${fetched:-}" ] || { echo "provision-gnatmetric: alr get produced no crate dir" >&2; exit 1; }
crate_dir="$abs_tools/$(basename "${fetched%/}")"
rm -rf "$crate_dir"
mv "${fetched%/}" "$crate_dir"
( cd "$crate_dir" && alr -n build ) >&2

bin="$crate_dir/bin/gnatmetric"
if [ ! -x "$bin" ]; then
  bin=$(find "$crate_dir" -type f -name gnatmetric -perm -u+x 2>/dev/null | head -n1 || true)
fi
[ -x "${bin:-}" ] || { echo "provision-gnatmetric: build did not produce gnatmetric" >&2; exit 1; }
printf '%s/gnatmetric\n' "$(cd "$(dirname "$bin")" && pwd)"
