#!/usr/bin/env python3
# purpose: Archive YouTube tango tracks as verified MP3s
# version: 20251227b
# owner: Paul Thompson
# logs: yt_tango_mp3.log

import argparse
import subprocess
import sys
import os
import shutil
import tempfile
import time
import json
from pathlib import Path

# =========================
# SINGLE SOURCE OF TRUTH
# =========================
SCRIPT_VERSION = "20251227b"

OWNER_TAG = "THOMPSON, Paul"
ENCODING_TAG = "MP3 CBR 320 kbps (yt-dlp)"
REQUIRED_BITRATE = 320_000
COUNTDOWN_SECONDS = 5

GENRES = ["tango", "vals", "milonga", "cortina"]

# Batch constants
BATCH_DONE_PREFIX = "#done "
BATCH_ERR_PREFIX = "[error:"
ABORT_AFTER_FAILURES = 5

# =========================
# ORCHESTRA DIRECTORY MAP
# =========================
ORCHESTRA_DIR_MAP = {
    "D'ARIENZO": "D'ARIENZO, Juan",
    "TANTURI": "TANTURI, Ricardo",
    "TROILO": "TROILO, Anibal",
}

# =========================
# UTILITIES
# =========================
def die(msg):
    print(f"FAILED ({msg})")
    sys.exit(1)

def run(cmd):
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

# =========================
# METADATA + BITRATE (UNCHANGED)
# =========================
def validate_bitrate(mp3_path):
    p = run([
        "ffprobe", "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=bit_rate",
        "-of", "json", mp3_path,
    ])
    if p.returncode != 0:
        return False
    data = json.loads(p.stdout)
    br = int(data["streams"][0].get("bit_rate", 0))
    return br >= REQUIRED_BITRATE

def write_metadata(mp3_path, title, artist, year):
    cmd = [
        "ffmpeg", "-y",
        "-i", mp3_path,
        "-metadata", f"title={title}",
        "-metadata", f"artist={artist}",
        "-metadata", f"date={year}",
        "-metadata", f"comment={ENCODING_TAG}",
        "-metadata", f"copyright={OWNER_TAG}",
        "-codec", "copy",
        mp3_path + ".tagged",
    ]
    p = run(cmd)
    if p.returncode != 0:
        return False
    os.replace(mp3_path + ".tagged", mp3_path)
    return True

def validate_metadata(mp3_path):
    p = run(["ffprobe", "-v", "error", "-show_entries", "format_tags", "-of", "json", mp3_path])
    if p.returncode != 0:
        return False
    tags = p.stdout
    for req in ["title", "artist", "date"]:
        if req not in tags:
            return False
    return OWNER_TAG in tags and ENCODING_TAG in tags

# =========================
# CORE PROCESSING (UNCHANGED)
# =========================
def process_entry(url, desc, genre, output_root, args):
    if genre not in GENRES:
        return False, "invalid genre"

    if args.dry_run:
        print("SUCCESS (.mp3 dry-run)")
        return True, None

    orchestra_token = desc.split()[0].upper()
    if orchestra_token not in ORCHESTRA_DIR_MAP:
        return False, "orchestra mapping missing"

    out_dir = Path(output_root) / genre / ORCHESTRA_DIR_MAP[orchestra_token]
    out_dir.mkdir(parents=True, exist_ok=True)

    target = out_dir / f"{desc}.mp3"

    if target.exists():
        if args.skip_if_exists:
            print("SUCCESS (.mp3 skipped: exists)")
            return True, None
        if not args.overwrite:
            return False, ".mp3 exists; use --overwrite"

    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "audio.m4a"
        mp3 = Path(tmp) / "out.mp3"

        p = run(["yt-dlp", "-f", "bestaudio", "-o", str(src), url])
        if p.returncode != 0:
            return False, ".webm / .m4a download error"

        p = run([
            "ffmpeg", "-y",
            "-i", str(src),
            "-vn",
            "-acodec", "libmp3lame",
            "-ab", "320k",
            str(mp3),
        ])
        if p.returncode != 0:
            return False, ".mp3 encode error"

        if not validate_bitrate(str(mp3)):
            return False, ".mp3 validation failed: bitrate"

        year = desc.split()[-1] if desc.split()[-1].isdigit() else "9999"
        if not write_metadata(str(mp3), desc, ORCHESTRA_DIR_MAP[orchestra_token], year):
            return False, ".mp3 metadata write error"

        if not validate_metadata(str(mp3)):
            return False, ".mp3 validation failed: metadata"

        shutil.move(str(mp3), target)

    print("SUCCESS (.mp3 overwritten)" if args.overwrite else "SUCCESS (.mp3 created)")
    return True, None

# =========================
# BATCH MODE (RESTORED)
# =========================
def process_batch(batch_file, output_root, args):
    failures = 0
    lines = Path(batch_file).read_text().splitlines()
    new_lines = []

    for line in lines:
        if line.startswith(BATCH_DONE_PREFIX) or line.startswith(BATCH_ERR_PREFIX):
            new_lines.append(line)
            continue

        try:
            url, desc, genre = [x.strip() for x in line.split("|", 2)]
        except ValueError:
            new_lines.append(f"{BATCH_ERR_PREFIX} malformed] {line}")
            failures += 1
            continue

        ok, err = process_entry(url, desc, genre, output_root, args)
        if ok:
            new_lines.append(f"{BATCH_DONE_PREFIX}{line}")
        else:
            new_lines.append(f"{BATCH_ERR_PREFIX} {err}] {line}")
            failures += 1

        if failures >= ABORT_AFTER_FAILURES:
            break

    Path(batch_file).write_text("\n".join(new_lines))

# =========================
# MAIN
# =========================
def main():
    ap = argparse.ArgumentParser(description="Archive YouTube tango tracks as verified MP3s.")
    ap.add_argument("--url")
    ap.add_argument("--desc")
    ap.add_argument("--genre", choices=GENRES)
    ap.add_argument("--batch-file")
    ap.add_argument("--output-root", default=os.getcwd())
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-if-exists", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--version", action="store_true")

    args = ap.parse_args()

    if args.version:
        print(SCRIPT_VERSION)
        return

    print("SUMMARY")
    print("-------")
    print("Mode   :", "BATCH" if args.batch_file else "SINGLE")
    print("Output :", args.output_root)
    print("DryRun :", args.dry_run)
    print()

    print(f"Execution will start in {COUNTDOWN_SECONDS} seconds.")
    print("Press Ctrl+C to abort.\n")
    if not args.yes:
        time.sleep(COUNTDOWN_SECONDS)

    if args.batch_file:
        process_batch(args.batch_file, args.output_root, args)
    else:
        if not (args.url and args.desc and args.genre):
            die("missing required args")
        ok, err = process_entry(args.url, args.desc, args.genre, args.output_root, args)
        if not ok:
            die(err)

if __name__ == "__main__":
    main()

