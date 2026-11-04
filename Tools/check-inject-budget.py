#!/usr/bin/env python3
"""Check that the selected tweaks fit into the YouTube binary's load-command area.

Theos injects one dylib per enabled tweak by adding an LC_LOAD_WEAK_DYLIB load
command (insert_dylib --inplace). All load commands have to fit between the
32-byte mach_header_64 and the file offset of the first non-empty __TEXT
section, which the linker reserves one page (0x4000) for.

When they do not fit, insert_dylib does not fail cleanly: it falls into a
rewrite path that stalls for hours before erroring out, e.g.

    ==> Error: Failed to inject YTUHD.dylib into YouTube.app

Each command costs 24 bytes plus the injected "@rpath/<dylib>" string, padded to
a multiple of 8, so the cost depends on the dylib's file name and not only on
the number of tweaks (48, 56 and 64 bytes occur in practice).

Usage:
    Tools/check-inject-budget.py --makefile Makefile \
        --binary Payload/YouTube.app/YouTube --tweaks "YouPiP iSponsorBlock"
"""

import argparse
import os
import re
import struct
import sys
import zipfile

LC_SEGMENT_64 = 0x19
MACH_HEADER_64 = 32
SECTION_64 = 80
MH_MAGIC_64 = 0xFEEDFACF
DYLIB_COMMAND_OVERHEAD = 24
MIN_COMMAND_SIZE = 40


def die(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def _first_section_offset(commands, ncmds):
    """Lowest file offset of a non-empty section in __TEXT."""
    best, offset = None, 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", commands, offset)
        if cmd == LC_SEGMENT_64 and commands[offset + 8:offset + 24] == b"__TEXT".ljust(16, b"\0"):
            nsects = struct.unpack_from("<I", commands, offset + 64)[0]
            for index in range(nsects):
                section = offset + 72 + index * SECTION_64
                size, position = struct.unpack_from("<QI", commands, section + 40)
                if size and position and (best is None or position < best):
                    best = position
        offset += cmdsize
    return best


def _parse(stream, name):
    header = stream.read(MACH_HEADER_64)
    if len(header) < MACH_HEADER_64:
        die(f"{name}: too short to be a 64-bit Mach-O")
    magic, _cpu, _sub, _type, ncmds, sizeofcmds, _flags, _res = struct.unpack("<IiiIIIII", header)
    if magic != MH_MAGIC_64:
        die(f"{name}: not a 64-bit Mach-O (magic 0x{magic:08x})")
    commands = stream.read(sizeofcmds)
    offset = _first_section_offset(commands, ncmds)
    if offset is None:
        die(f"{name}: no non-empty __TEXT section found")
    return ncmds, sizeofcmds, offset


def read_macho(path):
    """Return (ncmds, sizeofcmds, first_section_offset) for a file or an .ipa."""
    if path.endswith(".ipa"):
        with zipfile.ZipFile(path) as archive:
            member = next((n for n in archive.namelist() if n.endswith("Payload/YouTube.app/YouTube")), None)
            if member is None:
                die(f"{path}: Payload/YouTube.app/YouTube not found")
            with archive.open(member) as stream:
                return _parse(stream, member)
    if not os.path.isfile(path):
        die(f"{path}: not found")
    with open(path, "rb") as stream:
        return _parse(stream, path)


def read_makefile(path):
    """Return (repo dylib, uYou dylib, {tweak id: dylib name}, default tweaks)."""
    lines, buffer = [], ""
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            buffer += line.rstrip("\n")
            if buffer.endswith("\\"):
                buffer = buffer[:-1] + " "
                continue
            lines.append(buffer)
            buffer = ""
    if buffer:
        lines.append(buffer)

    variables = {}
    for line in lines:
        match = re.match(r"([A-Za-z0-9_.-]+)\s*[?:]?=\s*(.*)$", line)
        if match:
            variables.setdefault(match.group(1), match.group(2).strip())

    for key in ("TWEAK_NAME", "UYOU_DYLIB", "TWEAK_REGISTRY"):
        if key not in variables:
            die(f"{path}: {key} not found")

    dylibs = {}
    for identifier in variables["TWEAK_REGISTRY"].split():
        name = variables.get(f"{identifier}_DYLIB")
        if not name:
            die(f"{path}: no {identifier}_DYLIB for {identifier}")
        dylibs[identifier] = name

    return (f"{variables['TWEAK_NAME']}.dylib",
            os.path.basename(variables["UYOU_DYLIB"]),
            dylibs,
            variables.get("DEFAULT_TWEAKS", "").split())


def command_size(dylib_name):
    """Bytes an LC_LOAD_WEAK_DYLIB for this dylib consumes."""
    raw = DYLIB_COMMAND_OVERHEAD + len(f"@rpath/{dylib_name}") + 1
    return (raw + 7) // 8 * 8


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tweaks", default="", help="enabled tweak ids (default: DEFAULT_TWEAKS)")
    parser.add_argument("--makefile", default="Makefile")
    parser.add_argument("--binary", default="Payload/YouTube.app/YouTube")
    args = parser.parse_args()

    repo_dylib, uyou_dylib, registry, defaults = read_makefile(args.makefile)
    enabled = [t for t in re.split(r"[\s,]+", args.tweaks) if t] or defaults

    unknown = [t for t in enabled if t not in registry]
    if unknown:
        die(f"unknown tweak(s): {' '.join(unknown)} (valid: {' '.join(registry)})")

    ncmds, sizeofcmds, section_offset = read_macho(args.binary)
    budget = section_offset - MACH_HEADER_64
    free = budget - sizeofcmds

    entries = [(repo_dylib, "repo tweak"), (uyou_dylib, "uYou deb")]
    entries += [(registry[t] + ".dylib", t) for t in enabled]

    print(f"binary     : {args.binary}")
    print(f"ncmds      : {ncmds}")
    print(f"sizeofcmds : {sizeofcmds} B")
    print(f"budget     : {budget} B  (first __TEXT section at {section_offset} minus {MACH_HEADER_64} B mach_header)")
    print(f"free       : {free} B")
    print()
    total = 0
    for dylib, label in entries:
        size = command_size(dylib)
        total += size
        print(f"  {size:3} B  {dylib:<32} {label}")
    print(f"  {'-' * 62}")
    print(f"  {total} B of {free} B used by {len(entries)} dylibs")

    if total > free:
        print()
        die(f"{total - free} B too many: insert_dylib would stall for hours instead of "
            f"failing. Deselect tweaks worth at least {total - free} B.")

    left = free - total
    print(f"  -> {left} B left")
    if left < MIN_COMMAND_SIZE:
        print(f"warning: only {left} B left, less than the smallest possible command "
              f"({MIN_COMMAND_SIZE} B); a new YouTube build can break this.")


if __name__ == "__main__":
    main()
