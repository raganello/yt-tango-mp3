# yt_tango_mp3

Archive YouTube tango tracks as verified, tagged MP3 files with strict
engineering guarantees.

This project prioritizes correctness, reproducibility, and non-regression
over convenience or brevity.

---

## Features

- Single-track and batch processing modes
- Deterministic MP3 encoding (libmp3lame, 320 kbps CBR)
- Strict ID3 metadata writing and validation
- Safe overwrite / skip-if-exists semantics
- Dry-run mode (purely observational, no filesystem mutation)
- Retry and throttling logic for network resilience
- External black-box test harness with CI enforcement

---

## Usage

### Single track

```
yt_tango_mp3.py \
  --url "<youtube_url>" \
  --desc "<Orchestra - Title - Year>" \
  --genre tango \
  --output-root "<output_directory>" \
  --overwrite
```

### Batch mode

```
yt_tango_mp3.py \
  --batch-file "<batch_file.txt>" \
  --output-root "<output_directory>" \
  --overwrite
```

Batch files contain one job per line. Malformed lines are reported and skipped
without aborting the batch.

---

## Command-line flags

All flags are mandatory to preserve.

- --url
- --desc
- --genre {tango,vals,milonga,cortina}
- --batch-file
- --output-root
- --dry-run
- --skip-if-exists
- --overwrite
- --yes
- --version

---

## Tests (non-negotiable)

- Production code: yt_tango_mp3.py
- Tests only: run_yt_tango_mp3_tests.sh

Tests are:
- Black-box
- External
- Never embedded in production code

Run locally:

```
./run_yt_tango_mp3_tests.sh
```

CI enforces that all tests must pass before merge.

---

## Codex governance

This repository is governed by CODEX_CONTRACT.md.

Key rules:
- No silent regressions
- No refactors unless explicitly requested
- Tests must never be embedded in production code
- All behavior changes must be explicit and test-backed

Any automated change that violates these rules must be rejected.
