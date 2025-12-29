#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/yt_tango_mp3.py"
REPORT="${SCRIPT_DIR}/yt_tango_mp3_test_report.txt"

PASS_COUNT=0
FAIL_COUNT=0
TEST_INDEX=0
LAST_OUTPUT=""
LAST_EXIT=0

if rg -n '^[[:space:]]*TEST[[:space:]]+[0-9]+' "$0" >/tmp/yt_tango_mp3_test_guard.txt; then
    echo "ERROR: stray TEST line detected. All test titles must be emitted via functions." | tee -a "$REPORT"
    cat /tmp/yt_tango_mp3_test_guard.txt | tee -a "$REPORT"
    exit 1
fi
rm -f /tmp/yt_tango_mp3_test_guard.txt

: >"$REPORT"
echo "yt_tango_mp3 test report" >>"$REPORT"
echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"$REPORT"
echo >>"$REPORT"

log_line() {
    echo "$*" | tee -a "$REPORT"
}

emit_test_title() {
    local name="$1"
    TEST_INDEX=$((TEST_INDEX + 1))
    log_line "TEST ${TEST_INDEX}: ${name}"
}

run_command() {
    local output rc
    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e
    LAST_OUTPUT="$output"
    LAST_EXIT=$rc
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if ! grep -Fq -- "$needle" <<<"$haystack"; then
        log_line "ASSERT FAIL: expected output to contain: ${needle}"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if grep -Fq -- "$needle" <<<"$haystack"; then
        log_line "ASSERT FAIL: expected output to NOT contain: ${needle}"
        return 1
    fi
}

run_test() {
    local name="$1"
    shift
    emit_test_title "$name"
    set +e
    "$@"
    local rc=$?
    set -e
    if [ $rc -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        log_line "PASS"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_line "FAIL"
    fi
    echo >>"$REPORT"
}

run_test_expect_fail() {
    local name="$1"
    local expected_substring="$2"
    local forbidden_substring="$3"
    shift 3
    emit_test_title "$name"
    run_command "$@"
    local rc=0
    if [ $LAST_EXIT -eq 0 ]; then
        log_line "ASSERT FAIL: expected non-zero exit status"
        rc=1
    fi
    if [ -n "$expected_substring" ]; then
        assert_contains "$LAST_OUTPUT" "$expected_substring" || rc=1
    fi
    if [ -n "$forbidden_substring" ]; then
        assert_not_contains "$LAST_OUTPUT" "$forbidden_substring" || rc=1
    fi
    if [ $rc -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        log_line "PASS"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_line "FAIL"
        log_line "Output:"
        log_line "$LAST_OUTPUT"
    fi
    echo >>"$REPORT"
}

test_version() {
    local expected_version
    expected_version="$(python3 - <<'PY'
from pathlib import Path
import re
text = Path("yt_tango_mp3.py").read_text()
match = re.search(r'^SCRIPT_VERSION\\s*=\\s*"([^"]+)"', text, re.M)
print(match.group(1) if match else "")
PY
)"
    run_command python3 "$SCRIPT" --version
    if [ $LAST_EXIT -ne 0 ]; then
        log_line "ASSERT FAIL: --version exit code was $LAST_EXIT"
        return 1
    fi
    if [ -n "$expected_version" ]; then
        assert_contains "$LAST_OUTPUT" "$expected_version" || return 1
    fi
}

test_help_contains_examples() {
    run_command python3 "$SCRIPT" --help
    if [ $LAST_EXIT -ne 0 ]; then
        log_line "ASSERT FAIL: --help exit code was $LAST_EXIT"
        return 1
    fi
    assert_contains "$LAST_OUTPUT" "Examples:" || return 1
    assert_contains "$LAST_OUTPUT" "--batch-file" || return 1
    assert_contains "$LAST_OUTPUT" "--output-root" || return 1
}

test_single_dry_run_no_mutation() {
    local tmpdir expected_path
    tmpdir="$(mktemp -d)"
    expected_path="${tmpdir}/tango/BIAGI, Rodolfo/Biagi Test 1938.mp3"
    run_command python3 "$SCRIPT" \
        --url "https://example.invalid/video" \
        --desc "Biagi Test 1938" \
        --genre tango \
        --output-root "$tmpdir" \
        --dry-run \
        --yes
    if [ $LAST_EXIT -ne 0 ]; then
        log_line "ASSERT FAIL: dry-run exit code was $LAST_EXIT"
        rm -rf "$tmpdir"
        return 1
    fi
    assert_contains "$LAST_OUTPUT" "DRY-RUN: would create" || { rm -rf "$tmpdir"; return 1; }
    if [ -e "$expected_path" ]; then
        log_line "ASSERT FAIL: dry-run created file ${expected_path}"
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"
}

test_yes_skips_countdown() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    run_command python3 "$SCRIPT" \
        --url "https://example.invalid/video" \
        --desc "Biagi Test 1938" \
        --genre tango \
        --output-root "$tmpdir" \
        --dry-run \
        --yes
    if [ $LAST_EXIT -ne 0 ]; then
        log_line "ASSERT FAIL: dry-run exit code was $LAST_EXIT"
        rm -rf "$tmpdir"
        return 1
    fi
    assert_not_contains "$LAST_OUTPUT" "Press Ctrl+C" || { rm -rf "$tmpdir"; return 1; }
    rm -rf "$tmpdir"
}

test_batch_dry_run_no_mutation() {
    local tmpdir batch_file before after
    tmpdir="$(mktemp -d)"
    batch_file="${tmpdir}/batch.txt"
    printf "%s\n" "https://example.invalid/video|Biagi Test 1938|tango" >"$batch_file"
    before="$(cat "$batch_file")"
    run_command python3 "$SCRIPT" \
        --batch-file "$batch_file" \
        --output-root "$tmpdir" \
        --dry-run \
        --yes
    if [ $LAST_EXIT -ne 0 ]; then
        log_line "ASSERT FAIL: batch dry-run exit code was $LAST_EXIT"
        rm -rf "$tmpdir"
        return 1
    fi
    assert_contains "$LAST_OUTPUT" "Mode   : BATCH" || { rm -rf "$tmpdir"; return 1; }
    after="$(cat "$batch_file")"
    if [ "$before" != "$after" ]; then
        log_line "ASSERT FAIL: batch file changed during dry-run"
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"
}

run_test "Version flag prints version" test_version
run_test "Help includes examples and flags" test_help_contains_examples
run_test_expect_fail \
    "Missing required args fails" \
    "ERROR: missing required args" \
    "Press Ctrl+C" \
    python3 "$SCRIPT"
run_test "Single dry-run does not mutate output" test_single_dry_run_no_mutation
run_test "Countdown suppressed with --yes" test_yes_skips_countdown
run_test "Batch dry-run does not mutate batch file" test_batch_dry_run_no_mutation

log_line "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ ! -s "$REPORT" ]; then
    echo "ERROR: report file empty: $REPORT"
    exit 1
fi

if [ $FAIL_COUNT -ne 0 ]; then
    exit 1
fi
