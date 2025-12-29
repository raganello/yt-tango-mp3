#!/usr/bin/env bash
# purpose: Full regression test harness for yt_tango_mp3.py
# version: 20251229a
# owner: Paul Thompson

set -euo pipefail

SCRIPT="./yt_tango_mp3.py"
PYTHON="$(command -v python3)"

TEST_ROOT="$(pwd)/_test_output"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="yt_tango_mp3_test_report_${TIMESTAMP}.txt"

PASS_COUNT=0
FAIL_COUNT=0
TEST_COUNT=0

mkdir -p "${TEST_ROOT}"
: > "${REPORT}"

log() {
  echo "$*" | tee -a "${REPORT}"
}

run_test() {
  local name="$1"
  shift
  local -a cmd=("$@")

  TEST_COUNT=$((TEST_COUNT + 1))
  log ""
  log "TEST ${TEST_COUNT}: ${name}"
  log "CMD: ${cmd[*]}"

  if "${cmd[@]}" >>"${REPORT}" 2>&1; then
    log "RESULT: PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log "RESULT: FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

log "=== yt_tango_mp3 FULL TEST SUITE ==="
log "Started: $(date)"
log "Script: ${SCRIPT}"
log "==================================="

# --- TEST 1: --help works
run_test "CLI --help works" \
  "${PYTHON}" "${SCRIPT}" --help

# --- TEST 2: --version works
run_test "CLI --version works" \
  "${PYTHON}" "${SCRIPT}" --version

# --- TEST 3: missing args fails
run_test "Missing required args fails" \
  "${PYTHON}" "${SCRIPT}"

# --- TEST 4: dry-run does not create files
rm -rf "${TEST_ROOT}/dry"
mkdir -p "${TEST_ROOT}/dry"

run_test "Dry-run does not create files" \
  "${PYTHON}" "${SCRIPT}" \
    --url "https://youtu.be/jk1mR4WWMRk" \
    --desc "D'Arienzo (Reynal) Esclavas blancas - 1940" \
    --genre tango \
    --output "${TEST_ROOT}/dry" \
    --dry-run

if find "${TEST_ROOT}/dry" -type f | grep -q .; then
  log "Dry-run filesystem check: FAIL (files created)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  log "Dry-run filesystem check: PASS"
fi

# --- TEST 5: overwrite works
rm -rf "${TEST_ROOT}/single"
mkdir -p "${TEST_ROOT}/single"

run_test "Single overwrite works" \
  "${PYTHON}" "${SCRIPT}" \
    --url "https://youtu.be/jk1mR4WWMRk" \
    --desc "D'Arienzo (Reynal) Esclavas blancas - 1940" \
    --genre tango \
    --output "${TEST_ROOT}/single" \
    --overwrite

# --- TEST 6: batch mode works
BATCH_FILE="${TEST_ROOT}/batch.txt"
cat > "${BATCH_FILE}" <<EOF
https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango
EOF

run_test "Batch mode processes input file" \
  "${PYTHON}" "${SCRIPT}" \
    --batch-file "${BATCH_FILE}" \
    --output "${TEST_ROOT}/batch" \
    --overwrite


########################################
# TEST 7: Missing args returns non-zero exit code
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Missing args returns non-zero exit code" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && ! echo "$OUTPUT" | grep -q "Press Ctrl+C"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 8: Invalid genre fails fast
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Invalid genre fails fast" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT --url https://example.com --desc test --genre INVALID"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -qi "invalid" && ! echo "$OUTPUT" | grep -q "Press Ctrl+C"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 9: Batch file missing fails cleanly
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch file missing fails cleanly" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT --batch-file /no/such/file.txt --output $TEST_ROOT/missing_batch"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -qi "batch" && [ ! -d "$TEST_ROOT/missing_batch" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 10: Batch continues after malformed line
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch continues after malformed line" | tee -a "$REPORT"
BATCH_FILE="$TEST_ROOT/batch_mixed.txt"
cat > "$BATCH_FILE" <<EOF
https://youtu.be/jk1mR4WWMRk|Good Track|tango
THIS_IS_NOT_VALID
https://youtu.be/jk1mR4WWMRk|Another Track|tango
EOF
CMD="$PYTHON $SCRIPT --batch-file $BATCH_FILE --output $TEST_ROOT/batch_mixed --overwrite"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -qi "malformed"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 11: Simulated low disk space aborts safely
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Simulated low disk space aborts safely" | tee -a "$REPORT"
CMD="YT_TANGO_FORCE_LOW_DISK=1 $PYTHON $SCRIPT --url https://youtu.be/jk1mR4WWMRk --desc test --genre tango --output $TEST_ROOT/low_disk"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$(eval $CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -qi "disk"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 12: Network failure retry exhaustion
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Network failure retry exhaustion" | tee -a "$REPORT"
CMD="YT_TANGO_FORCE_NET_FAIL=1 $PYTHON $SCRIPT --url https://youtu.be/jk1mR4WWMRk --desc test --genre tango --output $TEST_ROOT/net_fail"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$(eval $CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -qi "retry"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 13: Batch dry-run is non-mutating
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch dry-run is non-mutating" | tee -a "$REPORT"
BATCH_FILE="$TEST_ROOT/batch_dry.txt"
cat > "$BATCH_FILE" <<EOF
https://youtu.be/jk1mR4WWMRk|Dry Run Track|tango
EOF
CMD="$PYTHON $SCRIPT --batch-file $BATCH_FILE --output $TEST_ROOT/batch_dry --dry-run"
echo "CMD: $CMD" | tee -a "$REPORT"
OUTPUT="$($CMD 2>&1)"
RC=$?
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 0 ] && [ ! -d "$TEST_ROOT/batch_dry" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"



# --- Self-test: report file non-empty
if [[ ! -s "${REPORT}" ]]; then
  echo "FATAL: report file is empty" >&2
  exit 2
fi

log ""
log "==================================="
log "Tests run : ${TEST_COUNT}"
log "Passed    : ${PASS_COUNT}"
log "Failed    : ${FAIL_COUNT}"
log "Report    : ${REPORT}"
log "==================================="

if [[ "${FAIL_COUNT}" -ne 0 ]]; then
  exit 1
fi

exit 0
