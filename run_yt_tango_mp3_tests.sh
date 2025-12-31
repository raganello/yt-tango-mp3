#!/usr/bin/env bash
# purpose: Full regression test harness for yt_tango_mp3.py
# version: 20251229a
# owner: Paul Thompson

set -euo pipefail

SCRIPT="./yt_tango_mp3.py"
SCRIPT_ABS="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
PYTHON="$(command -v python3)"
DEFAULT_OUTPUT_ROOT="$("${PYTHON}" -c "from pathlib import Path; print(Path('${SCRIPT_ABS}').resolve().parent)")"

TEST_ROOT="$(pwd)/_test_output"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="yt_tango_mp3_test_report_${TIMESTAMP}.txt"

PASS_COUNT=0
FAIL_COUNT=0
TEST_COUNT=0
REAL_RUN_FLAGS=()

if ! command -v yt-dlp >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
  REAL_RUN_FLAGS=(--dry-run)
fi

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
if [ "${#REAL_RUN_FLAGS[@]}" -ne 0 ]; then
  log "NOTICE: yt-dlp or ffmpeg missing; falling back to --dry-run for download tests."
fi

# --- TEST 1: --help works
run_test "CLI --help works" \
  "${PYTHON}" "${SCRIPT}" --help

# --- TEST 2: --version works
run_test "CLI --version works" \
  "${PYTHON}" "${SCRIPT}" --version

# --- TEST 3: missing args fails
########################################
# TEST 3: missing args fails
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Missing required args fails" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "missing required args"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

# --- TEST 4: dry-run does not create files
rm -rf "${TEST_ROOT}/dry"
mkdir -p "${TEST_ROOT}/dry"

run_test "Dry-run does not create files" \
  "${PYTHON}" "${SCRIPT}" \
    --url "https://youtu.be/jk1mR4WWMRk" \
    --desc "D'Arienzo (Reynal) Esclavas blancas - 1940" \
    --genre tango \
    --output-root "${TEST_ROOT}/dry" \
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
    --output-root "${TEST_ROOT}/single" \
    --overwrite \
    "${REAL_RUN_FLAGS[@]}"

# --- TEST 6: batch mode works
BATCH_FILE="${TEST_ROOT}/batch.txt"
cat > "${BATCH_FILE}" <<EOF
https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango
EOF

run_test "Batch mode processes input file" \
  "${PYTHON}" "${SCRIPT}" \
    --batch-file "${BATCH_FILE}" \
    --output-root "${TEST_ROOT}/batch" \
    --overwrite \
    "${REAL_RUN_FLAGS[@]}"

########################################
# TEST 7: Batch sidecar outputs in dry-run
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch sidecar outputs in dry-run" | tee -a "$REPORT"
BATCH_FILE="${TEST_ROOT}/batch_sidecar.txt"
SIDE_SUCCESS="https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango"
SIDE_FAIL="https://youtu.be/jk1mR4WWMRk|Bad Line|INVALID"
cat > "$BATCH_FILE" <<EOF
${SIDE_SUCCESS}
${SIDE_FAIL}
EOF
CMD=(
  "$PYTHON" "$SCRIPT"
  --batch-file "$BATCH_FILE"
  --output-root "$TEST_ROOT/batch_sidecar"
  --dry-run
  --yes
)
echo "CMD: ${CMD[*]}" | tee -a "$REPORT"
set +e
OUTPUT="$("${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
RESULTS_FILE="${BATCH_FILE}.results"
RETRY_FILE="${BATCH_FILE}.retry"
DONE_FILE="${BATCH_FILE}.done"
if [ "$RC" -eq 0 ] \
  && [ -f "$RESULTS_FILE" ] \
  && [ -f "$RETRY_FILE" ] \
  && [ -f "$DONE_FILE" ] \
  && grep -Fxq "$SIDE_FAIL" "$RETRY_FILE" \
  && ! grep -Fxq "$SIDE_SUCCESS" "$RETRY_FILE" \
  && grep -Fxq "$SIDE_SUCCESS" "$DONE_FILE" \
  && ! grep -Fxq "$SIDE_FAIL" "$DONE_FILE" \
  && [ "$(wc -l < "$RESULTS_FILE")" -ge 2 ] \
  && awk -F'\t' 'NF!=6 {bad=1} END {exit bad}' "$RESULTS_FILE" \
  && [ ! -d "$TEST_ROOT/batch_sidecar" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"


########################################
# TEST 8: Missing args returns non-zero exit code
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
# TEST 9: Invalid genre fails fast
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
# TEST 10: Batch file missing fails cleanly
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch file missing fails cleanly" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT --batch-file /no/such/file.txt --output-root $TEST_ROOT/missing_batch"
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
# TEST 11: Batch continues after malformed line
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch continues after malformed line" | tee -a "$REPORT"
BATCH_FILE="$TEST_ROOT/batch_mixed.txt"
cat > "$BATCH_FILE" <<EOF
https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango
THIS_IS_NOT_VALID
https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango
EOF
CMD=(
  "$PYTHON" "$SCRIPT"
  --batch-file "$BATCH_FILE"
  --output-root "$TEST_ROOT/batch_mixed"
  --overwrite
  "${REAL_RUN_FLAGS[@]}"
)
echo "CMD: ${CMD[*]}" | tee -a "$REPORT"
set +e
OUTPUT="$("${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 0 ] && echo "$OUTPUT" | grep -qi "malformed"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 12: Simulated low disk space aborts safely
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Simulated low disk space aborts safely" | tee -a "$REPORT"
CMD="YT_TANGO_FORCE_LOW_DISK=1 $PYTHON $SCRIPT --url https://youtu.be/jk1mR4WWMRk --desc test --genre tango --output-root $TEST_ROOT/low_disk"
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
# TEST 13: Network failure retry exhaustion
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Network failure retry exhaustion" | tee -a "$REPORT"
CMD="YT_TANGO_FORCE_NET_FAIL=1 $PYTHON $SCRIPT --url https://youtu.be/jk1mR4WWMRk --desc test --genre tango --output-root $TEST_ROOT/net_fail"
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
# TEST 14: Batch dry-run is non-mutating
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Batch dry-run is non-mutating" | tee -a "$REPORT"
BATCH_FILE="$TEST_ROOT/batch_dry.txt"
cat > "$BATCH_FILE" <<EOF
https://youtu.be/jk1mR4WWMRk|D'Arienzo (Reynal) Esclavas blancas - 1940|tango
EOF
CMD="$PYTHON $SCRIPT --batch-file $BATCH_FILE --output-root $TEST_ROOT/batch_dry --dry-run"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 0 ] && [ ! -d "$TEST_ROOT/batch_dry" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 15: Default output-root is used
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Default output-root is used" | tee -a "$REPORT"
CMD=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --dry-run
  --yes
)
echo "CMD: ${CMD[*]}" | tee -a "$REPORT"
set +e
OUTPUT="$("${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
OUTPUT_ROOT_LINE="$(echo "$OUTPUT" | awk -F'Output : ' '/^Output : / {print $2; exit}')"
if [ "$RC" -eq 0 ] && [ "$OUTPUT_ROOT_LINE" = "${DEFAULT_OUTPUT_ROOT}/" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 16: Default output-root matches dry-run and real execution
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Default output-root matches dry-run and real execution" | tee -a "$REPORT"
CMD_DRY=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --dry-run
  --yes
)
CMD_REAL=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --yes
)
echo "CMD (dry-run): ${CMD_DRY[*]}" | tee -a "$REPORT"
echo "CMD (real): YT_TANGO_FORCE_NET_FAIL=1 ${CMD_REAL[*]}" | tee -a "$REPORT"
set +e
OUTPUT_DRY="$("${CMD_DRY[@]}" 2>&1)"
RC_DRY=$?
OUTPUT_REAL="$(YT_TANGO_FORCE_NET_FAIL=1 "${CMD_REAL[@]}" 2>&1)"
RC_REAL=$?
set -e
echo "$OUTPUT_DRY" >> "$REPORT"
echo "$OUTPUT_REAL" >> "$REPORT"
OUTPUT_ROOT_DRY="$(echo "$OUTPUT_DRY" | awk -F'Output : ' '/^Output : / {print $2; exit}')"
OUTPUT_ROOT_REAL="$(echo "$OUTPUT_REAL" | awk -F'Output : ' '/^Output : / {print $2; exit}')"
if [ "$RC_DRY" -eq 0 ] && [ "$RC_REAL" -ne 0 ] \
  && [ "$OUTPUT_ROOT_DRY" = "${DEFAULT_OUTPUT_ROOT}/" ] \
  && [ "$OUTPUT_ROOT_REAL" = "${DEFAULT_OUTPUT_ROOT}/" ] \
  && [ "$OUTPUT_ROOT_DRY" = "$OUTPUT_ROOT_REAL" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 17: Default output-root does not change with cwd
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Default output-root does not change with cwd" | tee -a "$REPORT"
CWD_ONE="${TEST_ROOT}/cwd_one"
CWD_TWO="${TEST_ROOT}/cwd_two"
mkdir -p "${CWD_ONE}" "${CWD_TWO}"
CMD=(
  "$PYTHON" "$SCRIPT_ABS"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --dry-run
  --yes
)
echo "CMD (cwd_one): ${CMD[*]} (cwd=${CWD_ONE})" | tee -a "$REPORT"
echo "CMD (cwd_two): ${CMD[*]} (cwd=${CWD_TWO})" | tee -a "$REPORT"
set +e
OUTPUT_ONE="$(cd "${CWD_ONE}" && "${CMD[@]}" 2>&1)"
RC_ONE=$?
OUTPUT_TWO="$(cd "${CWD_TWO}" && "${CMD[@]}" 2>&1)"
RC_TWO=$?
set -e
echo "$OUTPUT_ONE" >> "$REPORT"
echo "$OUTPUT_TWO" >> "$REPORT"
OUTPUT_ROOT_ONE="$(echo "$OUTPUT_ONE" | awk -F'Output : ' '/^Output : / {print $2; exit}')"
OUTPUT_ROOT_TWO="$(echo "$OUTPUT_TWO" | awk -F'Output : ' '/^Output : / {print $2; exit}')"
if [ "$RC_ONE" -eq 0 ] && [ "$RC_TWO" -eq 0 ] \
  && [ "$OUTPUT_ROOT_ONE" = "${DEFAULT_OUTPUT_ROOT}/" ] \
  && [ "$OUTPUT_ROOT_TWO" = "${DEFAULT_OUTPUT_ROOT}/" ] \
  && [ "$OUTPUT_ROOT_ONE" != "${CWD_ONE}/" ] \
  && [ "$OUTPUT_ROOT_TWO" != "${CWD_TWO}/" ]; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 18: --output-root overrides default in dry-run and real mode
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: --output-root overrides default in dry-run and real mode" | tee -a "$REPORT"
OVERRIDE_ROOT="${TEST_ROOT}/override_root"
EXPECTED_OVERRIDE="Output : ${OVERRIDE_ROOT}/tango/D'ARIENZO, Juan/"
CMD_DRY=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --output-root "${OVERRIDE_ROOT}"
  --dry-run
  --yes
)
CMD_REAL=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --output-root "${OVERRIDE_ROOT}"
  --yes
)
echo "CMD (dry-run): ${CMD_DRY[*]}" | tee -a "$REPORT"
echo "CMD (real): YT_TANGO_FORCE_NET_FAIL=1 ${CMD_REAL[*]}" | tee -a "$REPORT"
set +e
OUTPUT_DRY="$("${CMD_DRY[@]}" 2>&1)"
RC_DRY=$?
OUTPUT_REAL="$(YT_TANGO_FORCE_NET_FAIL=1 "${CMD_REAL[@]}" 2>&1)"
RC_REAL=$?
set -e
echo "$OUTPUT_DRY" >> "$REPORT"
echo "$OUTPUT_REAL" >> "$REPORT"
if [ "$RC_DRY" -eq 0 ] && [ "$RC_REAL" -ne 0 ] \
  && echo "$OUTPUT_DRY" | grep -Fq "${EXPECTED_OVERRIDE}" \
  && echo "$OUTPUT_REAL" | grep -Fq "${EXPECTED_OVERRIDE}"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 19: Default output-root dry-run keeps existing file
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Default output-root dry-run keeps existing file" | tee -a "$REPORT"
DEFAULT_EXIST_ROOT="${TEST_ROOT}/default_exists"
EXIST_DESC="D'Arienzo (Reynal) Esclavas blancas - 1940"
EXIST_DIR="${DEFAULT_OUTPUT_ROOT}/tango/D'ARIENZO, Juan"
EXIST_FILE="${EXIST_DIR}/${EXIST_DESC}.mp3"
mkdir -p "${DEFAULT_EXIST_ROOT}"
mkdir -p "${EXIST_DIR}"
echo "stub" > "${EXIST_FILE}"
CMD=(
  "$PYTHON" "$SCRIPT_ABS"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "${EXIST_DESC}"
  --genre tango
  --dry-run
  --yes
)
echo "CMD: ${CMD[*]} (cwd=${DEFAULT_EXIST_ROOT})" | tee -a "$REPORT"
set +e
OUTPUT="$(cd "${DEFAULT_EXIST_ROOT}" && "${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 0 ] && echo "$OUTPUT" | grep -q "DRY-RUN: would keep existing"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 20: Default behavior when file exists (no skip/overwrite)
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Default behavior when file exists (no skip/overwrite)" | tee -a "$REPORT"
EXIST_ROOT="${TEST_ROOT}/exists_default"
EXIST_DESC="D'Arienzo (Reynal) Esclavas blancas - 1940"
EXIST_DIR="${EXIST_ROOT}/tango/D'ARIENZO, Juan"
EXIST_FILE="${EXIST_DIR}/${EXIST_DESC}.mp3"
mkdir -p "${EXIST_DIR}"
echo "stub" > "${EXIST_FILE}"
CMD=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "${EXIST_DESC}"
  --genre tango
  --output-root "${EXIST_ROOT}"
  --yes
)
echo "CMD: ${CMD[*]}" | tee -a "$REPORT"
set +e
OUTPUT="$("${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -ne 0 ] && echo "$OUTPUT" | grep -q "exists; use --overwrite"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 21: Countdown shown when --yes not provided
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: Countdown shown when --yes not provided" | tee -a "$REPORT"
CMD=(
  "$PYTHON" "$SCRIPT"
  --url "https://youtu.be/jk1mR4WWMRk"
  --desc "D'Arienzo (Reynal) Esclavas blancas - 1940"
  --genre tango
  --output-root "${TEST_ROOT}/countdown"
  --dry-run
)
echo "CMD: ${CMD[*]}" | tee -a "$REPORT"
set +e
OUTPUT="$("${CMD[@]}" 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
if [ "$RC" -eq 0 ] && echo "$OUTPUT" | grep -q "Press Ctrl+C to abort"; then
  echo "RESULT: PASS" | tee -a "$REPORT"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAIL" | tee -a "$REPORT"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
echo >> "$REPORT"

########################################
# TEST 22: --version matches header and is single-source
########################################
TEST_COUNT=$((TEST_COUNT+1))
echo "TEST ${TEST_COUNT}: --version matches header and is single-source" | tee -a "$REPORT"
CMD="$PYTHON $SCRIPT --version"
echo "CMD: $CMD" | tee -a "$REPORT"
set +e
OUTPUT="$($CMD 2>&1)"
RC=$?
set -e
echo "$OUTPUT" >> "$REPORT"
VERSION_HEADER="$(grep -m 1 '^# version:' "$SCRIPT" | awk -F': ' '{print $2}')"
VERSION_COUNT="$(grep -o "${VERSION_HEADER}" "$SCRIPT" | wc -l | tr -d ' ')"
if [ "$RC" -eq 0 ] && [ "$OUTPUT" = "$VERSION_HEADER" ] && [ "$VERSION_COUNT" -eq 1 ]; then
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
