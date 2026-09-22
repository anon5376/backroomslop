#!/bin/zsh
# Real two-process co-op acceptance; bounded runtime and isolated logs.
set -u
SEED="${1:-424242}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/backrooms-mp.XXXXXX")"
HOST_LOG="$LOG_DIR/host.log"
CLIENT_LOG="$LOG_DIR/client.log"
GODOT="${GODOT:-godot}"
HOST_PID=0 CLIENT_PID=0 WATCH_PID=0
cleanup() {
  for pid in "$HOST_PID" "$CLIENT_PID" "$WATCH_PID"; do
    if [ "$pid" -gt 0 ]; then kill "$pid" 2>/dev/null || true; fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"$GODOT" --headless --path "$DIR" --log-file "$HOST_LOG" -- --mp-host-test --seed "$SEED" &
HOST_PID=$!
sleep 1.5
"$GODOT" --headless --path "$DIR" --log-file "$CLIENT_LOG" -- --mp-join-test --mp-ip 127.0.0.1 &
CLIENT_PID=$!
(sleep "${MP_TEST_TIMEOUT:-90}"; kill "$HOST_PID" "$CLIENT_PID" 2>/dev/null) &
WATCH_PID=$!
wait "$CLIENT_PID"; CLIENT_EXIT=$?
wait "$HOST_PID"; HOST_EXIT=$?
kill "$WATCH_PID" 2>/dev/null || true
printf '%s\n' "--- host exit=$HOST_EXIT client exit=$CLIENT_EXIT ---" "Logs: $LOG_DIR"
grep -E 'MPTEST (PASS|FAIL)' "$HOST_LOG" "$CLIENT_LOG" || true
if [ "$HOST_EXIT" -ne 0 ] || [ "$CLIENT_EXIT" -ne 0 ] \
  || grep -Eq 'MPTEST FAIL|SCRIPT ERROR:|Parse Error:' "$HOST_LOG" "$CLIENT_LOG" \
  || ! grep -Eq 'MPTEST host done passes=[1-9][0-9]* fails=0' "$HOST_LOG" \
  || ! grep -Eq 'MPTEST client done passes=[1-9][0-9]* fails=0' "$CLIENT_LOG"; then
  printf '%s\n' 'MP TEST: FAILED'
  exit 1
fi
printf '%s\n' 'MP TEST: ALL PASS'
