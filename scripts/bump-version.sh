#!/bin/sh
# bump-version.sh — update the SData version string in all tracked locations.
#
# Usage: bump-version.sh <new-version> <changelog-summary>
#
#   new-version        e.g. 0.3.4
#   changelog-summary  one-line description of changes for changelog entries
#
# The script updates nine locations across eight files, appends dated entries
# to sdata.spec and debian/changelog, then optionally builds, tests, commits,
# and tags.  All steps are confirmed before destructive actions.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $(basename "$0") <new-version> <changelog-summary>" >&2
    echo "  e.g. $(basename "$0") 0.3.4 \"Fix foo; add bar.\"" >&2
    exit 1
fi

NEW_VER="$1"
SUMMARY="$2"

# Validate version format (N.N.N)
case "$NEW_VER" in
    [0-9]*.[0-9]*.[0-9]*)  ;;
    *)
        echo "Error: version must be in N.N.N format (got '$NEW_VER')" >&2
        exit 1
        ;;
esac

MAJOR=$(echo "$NEW_VER" | cut -d. -f1)
MINOR=$(echo "$NEW_VER" | cut -d. -f2)
PATCH=$(echo "$NEW_VER" | cut -d. -f3)

# Detect current version from the canonical source
OLD_VER=$(grep 'Version_Str' "$ROOT/src/sdata-config.ads" \
          | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$OLD_VER" ]; then
    echo "Error: could not detect current version from sdata-config.ads" >&2
    exit 1
fi

if [ "$OLD_VER" = "$NEW_VER" ]; then
    echo "Error: new version ($NEW_VER) is the same as the current version" >&2
    exit 1
fi

TODAY=$(date +%Y-%m-%d)
RPM_DATE=$(date +"%a %b %d %Y")
DEB_DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
MAINTAINER="John L. Ries <john@theyarnbard.com>"

echo "Bumping $OLD_VER -> $NEW_VER"
echo "Summary: $SUMMARY"
echo ""

# ---------------------------------------------------------------------------
# Helper: in-place sed that works on both GNU and BSD sed
# ---------------------------------------------------------------------------
sedi() {
    sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}

# ---------------------------------------------------------------------------
# 1. sdata-config.ads
# ---------------------------------------------------------------------------
FILE="$ROOT/src/sdata-config.ads"
sedi "s/Version_Patch : constant := $PATCH\b.*/Version_Patch : constant := $PATCH;/" "$FILE"
sedi "s/Version_Patch : constant := [0-9]*/Version_Patch : constant := $PATCH/" "$FILE"
sedi "s/Version_Str   : constant String := \"$OLD_VER\"/Version_Str   : constant String := \"$NEW_VER\"/" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 2. Makefile
# ---------------------------------------------------------------------------
FILE="$ROOT/Makefile"
sedi "s/^VERSION[[:space:]]*:=.*/VERSION          := $NEW_VER/" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 3. alire.toml
# ---------------------------------------------------------------------------
FILE="$ROOT/alire.toml"
sedi "s/^version = \"$OLD_VER\"/version = \"$NEW_VER\"/" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 4. slackware/sdata.SlackBuild
# ---------------------------------------------------------------------------
FILE="$ROOT/slackware/sdata.SlackBuild"
sedi "s/VERSION=\${VERSION:-$OLD_VER}/VERSION=\${VERSION:-$NEW_VER}/" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 5. man/man1/sdata.1
# ---------------------------------------------------------------------------
FILE="$ROOT/man/man1/sdata.1"
sedi "s/\"sdata $OLD_VER\"/\"sdata $NEW_VER\"/" "$FILE"
sedi "s/\"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\" \"sdata /\"$TODAY\" \"sdata /" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 6. README.md  (version strings in example output and filenames)
# ---------------------------------------------------------------------------
FILE="$ROOT/README.md"
# Use a loop to avoid sed extended-regex portability issues with dots
OLD_ESC=$(echo "$OLD_VER" | sed 's/\./\\./g')
NEW_ESC="$NEW_VER"
sed "s/$OLD_ESC/$NEW_ESC/g" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 7. sdata.spec — version field + new changelog entry
# ---------------------------------------------------------------------------
FILE="$ROOT/sdata.spec"
sedi "s/^Version:[[:space:]]*.*/Version:        $NEW_VER/" "$FILE"
# Prepend new changelog entry after the %changelog line using a temp file
# to avoid shell escape issues with embedded newlines.
awk -v date="$RPM_DATE" -v maint="$MAINTAINER" \
    -v ver="$NEW_VER" -v summary="$SUMMARY" '
    /^%changelog/ { print; print "* " date " " maint " - " ver "-1"; print "- " summary; print ""; next }
    { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
echo "  updated $FILE"

# ---------------------------------------------------------------------------
# 8. debian/changelog — prepend new entry
# ---------------------------------------------------------------------------
FILE="$ROOT/debian/changelog"
# Write new entry to a temp file then concatenate with existing changelog.
TMPENTRY=$(mktemp)
cat > "$TMPENTRY" <<DEBEOF
sdata ($NEW_VER-1) unstable; urgency=medium

  * $SUMMARY

 -- $MAINTAINER  $DEB_DATE

DEBEOF
cat "$TMPENTRY" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
rm -f "$TMPENTRY"
echo "  updated $FILE"

echo ""

# ---------------------------------------------------------------------------
# Verify no old version strings remain in tracked files
# ---------------------------------------------------------------------------
REMAINING=$(grep -rl "$OLD_VER" \
    "$ROOT/src/sdata-config.ads" \
    "$ROOT/Makefile" \
    "$ROOT/alire.toml" \
    "$ROOT/slackware/sdata.SlackBuild" \
    "$ROOT/man/man1/sdata.1" \
    "$ROOT/README.md" \
    "$ROOT/sdata.spec" \
    "$ROOT/debian/changelog" \
    2>/dev/null) || true

if [ -n "$REMAINING" ]; then
    echo "Warning: old version string '$OLD_VER' still present in:"
    echo "$REMAINING" | sed 's/^/  /'
    echo "These may be legitimate historical entries (e.g. changelogs)."
    echo ""
fi

# ---------------------------------------------------------------------------
# Optional: build and test
# ---------------------------------------------------------------------------
printf 'Run make build and make check? [y/N] '
read -r RUN_TESTS
case "$RUN_TESTS" in
    [yY]*)
        cd "$ROOT"
        make build
        make check
        ;;
esac

echo ""

# ---------------------------------------------------------------------------
# Optional: commit and tag
# ---------------------------------------------------------------------------
printf 'Commit and tag v%s? [y/N] ' "$NEW_VER"
read -r DO_COMMIT
case "$DO_COMMIT" in
    [yY]*)
        cd "$ROOT"
        git add \
            src/sdata-config.ads \
            Makefile \
            alire.toml \
            slackware/sdata.SlackBuild \
            "man/man1/sdata.1" \
            README.md \
            sdata.spec \
            debian/changelog
        git commit -m "Bump version to $NEW_VER"
        git tag -a "v$NEW_VER" -m "Version $NEW_VER"
        echo "Tagged v$NEW_VER"
        ;;
esac
