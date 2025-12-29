#!/usr/bin/env python3
# purpose: Archive YouTube tango tracks as verified MP3s
# version: 20251229a
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
    "BASSO": "BASSO, Osvaldo",
    "BIAGI": "BIAGI, Rodolfo",
    "CALO": "CALO, Miguel",
    "CANARO": "CANARO, Francisco",
    "D'AGOSTINO": "D'AGOSTINO, Angel",
    "D'ARIENZO": "D'ARIENZO, Juan",
    "DE ANGELIS": "DE ANGELIS, Alfredo",
    "DE CARO": "DE CARO, Julio",
    "DEMARE": "DEMARE, Lucio",
    "DI SARLI": "DI SARLI, Carlos",
    "DONATO": "DONATO, Edgardo",
    "FIRPO": "FIRPO, Roberto",
    "FRESEDO": "FRESEDO, Osvaldo",
    "GOBBI": "GOBBI, Alfredo",
    "LAURENZ": "LAURENZ, Pedro",
    "LOMUTO": "LOMUTO, Francisco",
    "MALERBA": "MALERBA, Ricardo",
    "MORES": "MORES, Mariano",
    "PIAZZOLLA": "PIAZZOLLA, Astor",
    "PUGLIESE": "PUGLIESE, Osvaldo",
    "RODRIGUEZ": "RODRIGUEZ, Enrique",
    "SALGAN": "SALGAN, Horacio",
    "TANTURI": "TANTURI, Ricardo",
    "TROILO": "TROILO, Anibal",
    "VARELA": "VARELA, Hector",
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

def get_script_version():
    try:
        with open(__file__, "r", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("# version:"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        return "unknown"
    return "unknown"

# =========================
# METADATA + BITRATE (UNCHANGED)
# =========================
def validate_bitrate(mp3_path):
    p = run([
        "ffprobe", "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=bit_rate,codec_name",
        "-show_entries", "format=duration,size,bit_rate",
        "-of", "json", mp3_path,
    ])
    if p.returncode != 0:
        return False
    data = json.loads(p.stdout)
    stream = data.get("streams", [{}])[0]
    format_data = data.get("format", {})
    stream_br = int(stream.get("bit_rate") or 0)
    format_br = int(format_data.get("bit_rate") or 0)
    if stream_br >= REQUIRED_BITRATE or format_br >= REQUIRED_BITRATE:
        return True
    # ffprobe can under-report MP3 CBR bit_rate; fall back to size/duration.
    # This keeps validation strict while allowing expected variance.
    if stream.get("codec_name") != "mp3":
        return False
    try:
        duration = float(format_data.get("duration") or 0)
        size = float(format_data.get("size") or 0)
    except (TypeError, ValueError):
        return False
    if duration <= 0 or size <= 0:
        return False
    avg_bitrate = (size * 8) / duration
    return avg_bitrate >= REQUIRED_BITRATE * 0.95

def write_metadata(mp3_path, title, artist, year):
    tagged_path = mp3_path + ".tagged.mp3"
    cmd = [
        "ffmpeg", "-y",
        "-i", mp3_path,
        "-metadata", f"title={title}",
        "-metadata", f"artist={artist}",
        "-metadata", f"date={year}",
        "-metadata", f"comment={ENCODING_TAG}",
        "-metadata", f"copyright={OWNER_TAG}",
        "-codec", "copy",
        tagged_path,
    ]
    p = run(cmd)
    if p.returncode != 0:
        if os.path.exists(tagged_path):
            os.remove(tagged_path)
        return False
    os.replace(tagged_path, mp3_path)
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

    if os.environ.get("YT_TANGO_FORCE_LOW_DISK") == "1":
        return False, "disk space low"

    if os.environ.get("YT_TANGO_FORCE_NET_FAIL") == "1":
        retries = 3
        for attempt in range(1, retries + 1):
            print(f"WARNING: network failure simulated (retry {attempt}/{retries})")
        return False, "retry attempts exhausted"

    orchestra_token = desc.split()[0].upper()
    if orchestra_token not in ORCHESTRA_DIR_MAP:
        return False, "orchestra mapping missing"

    out_dir = Path(output_root) / genre / ORCHESTRA_DIR_MAP[orchestra_token]
    target = out_dir / f"{desc}.mp3"

    # DRY-RUN MUST be strictly observational: no filesystem mutations.
    if args.dry_run:
        action = "create"
        if target.exists():
            if args.skip_if_exists:
                print(f"DRY-RUN: would skip existing {target}")
                return True, None
            if not args.overwrite:
                print(f"DRY-RUN: would fail (.mp3 exists; use --overwrite) {target}")
                return True, None
            action = "overwrite"
        print(f"DRY-RUN: would {action} {target}")
        return True, None

    out_dir.mkdir(parents=True, exist_ok=True)

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
    successes = 0
    lines = Path(batch_file).read_text().splitlines()
    new_lines = []

    for line_number, line in enumerate(lines, start=1):
        if line.startswith(BATCH_DONE_PREFIX) or line.startswith(BATCH_ERR_PREFIX):
            new_lines.append(line)
            continue

        try:
            url, desc, genre = [x.strip() for x in line.split("|", 2)]
            if not (url and desc and genre):
                raise ValueError
        except ValueError:
            print(f"WARNING: line {line_number} malformed; expected url|desc|genre", file=sys.stderr)
            new_lines.append(f"{BATCH_ERR_PREFIX} malformed] {line}")
            failures += 1
            continue

        ok, err = process_entry(url, desc, genre, output_root, args)
        if ok:
            new_lines.append(f"{BATCH_DONE_PREFIX}{line}")
            successes += 1
        else:
            new_lines.append(f"{BATCH_ERR_PREFIX} {err}] {line}")
            failures += 1

        if failures >= ABORT_AFTER_FAILURES:
            break

    if not args.dry_run:
        Path(batch_file).write_text("\n".join(new_lines))
    return successes > 0

# =========================
# MAIN
# =========================
def main():
    examples = (
        "Examples:\n"
        "  Single: yt_tango_mp3.py --url <url> --desc \"<desc>\" --genre tango --output-root \"<dir>\" --overwrite\n"
        "  Batch:  yt_tango_mp3.py --batch-file \"<file>\" --output-root \"<dir>\" --overwrite"
    )
    ap = argparse.ArgumentParser(
        description="Archive YouTube tango tracks as verified MP3s.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=examples,
    )
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
        print(get_script_version())
        return
    if not (args.batch_file or (args.url and args.desc and args.genre)):
        print("ERROR: missing required args", file=sys.stderr)
        sys.exit(2)
    if args.batch_file and not Path(args.batch_file).is_file():
        print("ERROR: batch file missing", file=sys.stderr)
        sys.exit(2)

    output_display = Path(args.output_root).resolve()
    if args.genre and args.desc:
        orchestra_token = args.desc.split()[0].upper()
        orchestra_dir = ORCHESTRA_DIR_MAP.get(orchestra_token)
        if orchestra_dir:
            output_display = output_display / args.genre / orchestra_dir
    print("SUMMARY")
    print("-------")
    print("Mode   :", "BATCH" if args.batch_file else "SINGLE")
    print("Output :", f"{output_display}{os.sep}")
    print("DryRun :", args.dry_run)
    print()

    if not args.yes:
        message_template = "Press Ctrl+C to abort else execution will start in {N} seconds."
        remaining = COUNTDOWN_SECONDS
        sys.stdout.write(message_template.format(N=remaining))
        sys.stdout.flush()
        while remaining > 0:
            time.sleep(1)
            remaining -= 1
            sys.stdout.write("\r" + message_template.format(N=remaining))
            sys.stdout.flush()
        sys.stdout.write("\n")
        sys.stdout.flush()

    if args.batch_file:
        ok = process_batch(args.batch_file, args.output_root, args)
        if not ok:
            die("batch failed")
    else:
        if not (args.url and args.desc and args.genre):
            die("missing required args")
        ok, err = process_entry(args.url, args.desc, args.genre, args.output_root, args)
        if not ok:
            die(err)

if __name__ == "__main__":
    main()
