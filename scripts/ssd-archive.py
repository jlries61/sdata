#!/usr/bin/env python3
"""ssd-archive.py -- move a shipped workstream from `active:` to `archived:` in
.ssd/current.yml, and keep that file small.

Why this exists: shipping a release is scripted (scripts/bump-version.sh) but
the tracker step after it was a hand edit of a YAML file, and it was forgotten
(milestone 2026-09-19, SK-2: a tagged, CI-green workstream still read
`phase: review` two days later). This script makes the step one command that
bump-version.sh offers at tag time. It is a prompt-driven convenience, never an
automatic action.

.ssd/ is gitignored and local to the maintainer: every mode exits 0 quietly
when .ssd/current.yml does not exist (CI clones, other contributors).

Usage:
    scripts/ssd-archive.py --list
        Print the slug of each active workstream, one per line.
    scripts/ssd-archive.py <slug> [--landed TEXT | --landed-file PATH|-]
                                  [--completed ISO8601] [--dry-run]
        Archive <slug>. A landing note longer than 300 characters is written in
        full to .ssd/features/<slug>/landed.md and current.yml keeps a short
        summary plus a pointer, so current.yml stays machine state rather than
        becoming a changelog.
    scripts/ssd-archive.py --slim [--apply]
        One-time migration: apply the same rule to existing archived entries
        whose `landed:` is long. Dry run unless --apply; --apply first copies
        current.yml to current.yml.bak-<date> (never overwriting an old backup).

    --ssd-dir DIR   use DIR instead of <repo>/.ssd

Safety: refuses to write unless the file has exactly one `active:` and one
`archived:` key (a duplicate top-level key silently shadows entries in YAML --
this has happened in this repo), verifies the new text before touching disk,
and replaces the file atomically (temp file + rename). Python 3 stdlib only,
matching the other scripts here; the YAML subset it edits (single-quoted
`landed:` scalars) is handled by hand rather than by reformatting the whole
file through a YAML library.
"""

import argparse
import datetime
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANDED_LIMIT = 300


class ArchiveError(Exception):
    pass


# ---------------------------------------------------------------- parsing ---

def split_sections(text):
    """Return (head, active_hdr, active_body, archived_hdr, archived_body) as
    line lists. Raises ArchiveError on a missing or duplicated top-level key."""
    lines = text.split("\n")
    act = [i for i, l in enumerate(lines) if l.startswith("active:")]
    arc = [i for i, l in enumerate(lines) if l.startswith("archived:")]
    if len(act) != 1 or len(arc) != 1:
        raise ArchiveError(
            f"expected exactly one 'active:' and one 'archived:' key, found "
            f"{len(act)} and {len(arc)} -- refusing to edit (a duplicate key "
            f"shadows entries; fix by hand first)")
    a, b = act[0], arc[0]
    if b < a:
        raise ArchiveError("'archived:' precedes 'active:' -- unexpected layout")
    return lines[:a], lines[a], lines[a + 1:b], lines[b], lines[b + 1:]


def split_entries(body):
    """Split a list body into entry blocks (each starting at '- slug:').
    A non-blank line before the first entry is an error."""
    blocks, cur = [], None
    for line in body:
        if line.startswith("- slug:"):
            cur = [line]
            blocks.append(cur)
        elif cur is not None:
            cur.append(line)
        elif line.strip():
            raise ArchiveError(f"unexpected line before first entry: {line!r}")
    return blocks


def block_slug(block):
    m = re.match(r"- slug:\s*(\S+)", block[0])
    return m.group(1) if m else None


def block_field(block, key, default="null"):
    for line in block[1:]:
        m = re.match(rf"  {re.escape(key)}:\s*(.*)$", line)
        if m:
            return m.group(1).rstrip()
    return default


def landed_span(block):
    """(start, end) line indices of the `landed:` field incl. continuation
    lines, or None."""
    for i, line in enumerate(block):
        if line.startswith("  landed:"):
            j = i + 1
            while j < len(block) and (block[j].startswith("    ") or not block[j].strip()) \
                    and not block[j].startswith("- "):
                j += 1
            # trailing blank lines belong to the entry separator, not the field
            while j > i + 1 and not block[j - 1].strip():
                j -= 1
            return i, j
    return None


def decode_single_quoted(lines):
    """Decode a folded YAML single-quoted scalar given its raw lines (the first
    with the 'landed:' key already removed). Returns None if not single-quoted."""
    raw = " ".join(l.strip() for l in lines).strip()
    if len(raw) >= 2 and raw[0] == "'" and raw[-1] == "'":
        return raw[1:-1].replace("''", "'")
    return None


def encode_single_quoted(s):
    return "'" + " ".join(s.split()).replace("'", "''") + "'"


def alloc_note_name(slug, taken, exists):
    """First free note filename for <slug>: landed.md, then landed-2.md, ...
    A slug can legitimately be archived more than once (one entry per
    iteration), and a hand-written note may already exist; neither is an
    error, and nothing is ever overwritten. `taken` is the set of
    (slug, name) already allocated in this run; `exists(slug, name)` reports
    files already on disk."""
    n = 1
    while True:
        name = "landed.md" if n == 1 else f"landed-{n}.md"
        if (slug, name) not in taken and not exists(slug, name):
            taken.add((slug, name))
            return name
        n += 1


def summarize(text, limit=LANDED_LIMIT):
    """First ~limit characters, cut at a sentence end if that keeps a useful
    amount, else at a word boundary; adds an ellipsis when it truncates."""
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    cut = text[:limit]
    ends = [m.end() for m in re.finditer(r"[.;] ", cut)]
    good = [e for e in ends if e >= 80]
    if good:
        return cut[:good[-1]].rstrip()
    return cut[:cut.rfind(" ")].rstrip() + " ..."


# --------------------------------------------------------------- verifying ---

def verify(new_text, expect_entries):
    lines = new_text.split("\n")
    if sum(1 for l in lines if l.startswith("active:")) != 1 or \
       sum(1 for l in lines if l.startswith("archived:")) != 1:
        raise ArchiveError("verification failed: top-level key count changed")
    n = sum(1 for l in lines if l.startswith("- slug:"))
    if n != expect_entries:
        raise ArchiveError(f"verification failed: entry count {n} != {expect_entries}")
    try:
        import yaml  # optional; only used as an extra check when installed
    except ImportError:
        return
    try:
        d = yaml.safe_load(new_text)
    except Exception as e:  # noqa: BLE001 - any parse failure is a refusal
        raise ArchiveError(f"verification failed: result is not valid YAML: {e}")
    total = len(d.get("active") or []) + len(d.get("archived") or [])
    if total != expect_entries:
        raise ArchiveError(f"verification failed: YAML entry count {total} != {expect_entries}")


def count_entries(text):
    return sum(1 for l in text.split("\n") if l.startswith("- slug:"))


# ------------------------------------------------------------------- modes ---

def list_active(text):
    _, _, active_body, _, _ = split_sections(text)
    return [block_slug(b) for b in split_entries(active_body)]


def archive_entry(text, slug, landed_full, completed, exists=lambda slug, name: False):
    """Return (new_text, (filename, full_note) or None). The second element is
    set when the note is long enough to live in features/<slug>/<filename>."""
    head, a_hdr, a_body, r_hdr, r_body = split_sections(text)
    blocks = split_entries(a_body)
    match = [b for b in blocks if block_slug(b) == slug]
    if not match:
        archived = [block_slug(b) for b in split_entries(r_body)]
        if slug in archived:
            raise ArchiveError(f"already archived: {slug}")  # caller treats as no-op
        raise ArchiveError(f"no active workstream named {slug!r}")
    entry = match[0]
    landed_full = " ".join((landed_full or
                            "Archived; no landing note supplied.").split())
    long_note = len(landed_full) > LANDED_LIMIT
    landed_line = summarize(landed_full)
    note_name = alloc_note_name(slug, set(), exists) if long_note else None
    if long_note:
        landed_line += f" [full: features/{slug}/{note_name}]"
    new_block = [
        f"- slug: {slug}",
        "  phase: done",
        f"  iteration: {block_field(entry, 'iteration')}",
        f"  started: {block_field(entry, 'started')}",
        f"  completed: '{completed}'",
        f"  branch: {block_field(entry, 'branch')}",
        f"  gate_rounds: {block_field(entry, 'gate_rounds', '0')}",
        f"  landed: {encode_single_quoted(landed_line)}",
    ]
    remaining = [b for b in blocks if b is not entry]
    new_active = [l for b in remaining for l in b]
    a_hdr2 = "active:" if remaining else "active: []"
    r_blocks = split_entries(r_body)
    new_r = new_block + [l for b in r_blocks for l in b]
    out = head + [a_hdr2] + new_active + ["archived:"] + new_r
    new_text = "\n".join(out)
    if not new_text.endswith("\n"):
        new_text += "\n"
    verify(new_text, count_entries(text))
    return new_text, ((note_name, landed_full) if long_note else None)


def slim_archived(text, limit=LANDED_LIMIT, exists=lambda slug, name: False):
    """Return (new_text, [(slug, filename, full_note), ...], [warning, ...])."""
    head, a_hdr, a_body, r_hdr, r_body = split_sections(text)
    r_blocks = split_entries(r_body)
    moved, warnings, out_blocks, taken = [], [], [], set()
    for block in r_blocks:
        slug = block_slug(block)
        span = landed_span(block)
        if span is None:
            out_blocks.append(block)
            continue
        i, j = span
        first = block[i][len("  landed:"):]
        full = decode_single_quoted([first] + block[i + 1:j])
        if full is None:
            # Short plain scalars are fine as they are; only flag a long one
            # this tool cannot decode.
            raw_len = len(" ".join(" ".join([first] + block[i + 1:j]).split()))
            if raw_len > limit:
                warnings.append(f"{slug}: long landed: is not a single-quoted "
                                f"scalar; left alone")
            out_blocks.append(block)
            continue
        full = " ".join(full.split())
        if len(full) <= limit or "[full: features/" in full:
            out_blocks.append(block)
            continue
        name = alloc_note_name(slug, taken, exists)
        line = summarize(full, limit) + f" [full: features/{slug}/{name}]"
        moved.append((slug, name, full))
        out_blocks.append(block[:i] + [f"  landed: {encode_single_quoted(line)}"] + block[j:])
    a_out = "\n".join(head + [a_hdr] + a_body + [r_hdr] +
                      [l for b in out_blocks for l in b])
    if not a_out.endswith("\n"):
        a_out += "\n"
    verify(a_out, count_entries(text))
    return a_out, moved, warnings


# ---------------------------------------------------------------- file I/O ---

def write_atomic(path, text):
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_landed_md(ssd_dir, slug, name, full):
    d = ssd_dir / "features" / slug
    d.mkdir(parents=True, exist_ok=True)
    p = d / name
    with open(p, "x") as f:  # "x": fail rather than ever overwrite a note
        f.write(f"# {slug} -- landing note\n\n{full}\n")
    return p


def note_exists(ssd_dir):
    return lambda slug, name: (ssd_dir / "features" / slug / name).exists()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--slim", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--landed")
    ap.add_argument("--landed-file")
    ap.add_argument("--completed")
    ap.add_argument("--ssd-dir", default=str(ROOT / ".ssd"))
    args = ap.parse_args(argv)

    ssd = Path(args.ssd_dir)
    cur = ssd / "current.yml"
    if not cur.is_file():
        return 0  # no local tracker: nothing to do, and not an error
    text = cur.read_text()

    try:
        if args.list:
            for s in list_active(text):
                print(s)
            return 0

        if args.slim:
            new_text, moved, warns = slim_archived(text, exists=note_exists(ssd))
            for w in warns:
                print(f"warning: {w}", file=sys.stderr)
            print(f"{len(moved)} archived entr{'y' if len(moved) == 1 else 'ies'} "
                  f"with a long landed: field; current.yml "
                  f"{len(text.encode())} -> {len(new_text.encode())} bytes")
            if not args.apply:
                print("dry run; re-run with --apply to write")
                return 0
            bak = cur.with_name(f"current.yml.bak-{datetime.date.today().isoformat()}")
            if not bak.exists():
                bak.write_text(text)
            for slug, name, full in moved:
                write_landed_md(ssd, slug, name, full)
            write_atomic(cur, new_text)
            print(f"wrote {cur} (backup: {bak.name})")
            return 0

        if not args.slug:
            ap.error("give a <slug>, or use --list / --slim")
        if args.landed_file:
            note = (sys.stdin.read() if args.landed_file == "-"
                    else Path(args.landed_file).read_text())
        else:
            note = args.landed
        completed = args.completed or datetime.datetime.now(
            datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        try:
            new_text, note_file = archive_entry(text, args.slug, note, completed,
                                                exists=note_exists(ssd))
        except ArchiveError as e:
            if str(e).startswith("already archived"):
                print(f"{args.slug}: already archived; nothing to do")
                return 0
            raise
        if args.dry_run:
            print(f"would archive {args.slug}"
                  + (f" (long note -> features/{args.slug}/{note_file[0]})" if note_file else ""))
            return 0
        if note_file:
            write_landed_md(ssd, args.slug, *note_file)
        prev = cur.with_name("current.yml.prev")
        prev.write_text(text)
        write_atomic(cur, new_text)
        print(f"archived {args.slug} (previous state kept as {prev.name})")
        return 0
    except ArchiveError as e:
        print(f"ssd-archive: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
