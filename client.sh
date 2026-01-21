#!/bin/bash
# iperf3 upload stress test client with outage detection

SERVER=${1:-""}
PORT=${2:-5201}
PARALLEL=8
INTERVAL=10

if [ -z "$SERVER" ]; then
    echo "Usage: $0 <server_ip> [port]"
    echo ""
    echo "Example: $0 192.168.1.100"
    exit 1
fi

START_TIME=$(date +%s)
LOGFILE="$(date '+%Y-%m-%d_%H-%M-%S').log"
FIFO=$(mktemp -u)
mkfifo "$FIFO"
ZERO_COUNT=0
IPERF_PID=""

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

log_exit() {
    local reason=$1
    ELAPSED=$(($(date +%s) - START_TIME))
    echo ""
    echo "$reason"
    echo "Total runtime: $(format_duration $ELAPSED)"
    echo "---" >> "$LOGFILE"
    echo "Ended: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
    echo "Reason: $reason" >> "$LOGFILE"
    echo "Total runtime: $(format_duration $ELAPSED)" >> "$LOGFILE"
    rm -f "$FIFO"
}

cleanup() {
    if [ -n "$IPERF_PID" ] && kill -0 "$IPERF_PID" 2>/dev/null; then
        kill "$IPERF_PID" 2>/dev/null
    fi
    log_exit "Stopped by user."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

echo "Upload stress test to $SERVER:$PORT with $PARALLEL parallel streams"
echo "Reporting every $INTERVAL seconds"
echo "Logging to: $LOGFILE"
echo "Press Ctrl+C to stop"
echo ""

echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
echo "Server: $SERVER:$PORT" >> "$LOGFILE"
echo "---" >> "$LOGFILE"

ELAPSED=$(($(date +%s) - START_TIME))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Starting iperf3 test..."

# Run iperf3, output to FIFO
iperf3 -c "$SERVER" -p "$PORT" -P "$PARALLEL" -t 0 -i "$INTERVAL" --forceflush > "$FIFO" 2>&1 &
IPERF_PID=$!

# Read from FIFO
while read -r line; do
    ELAPSED=$(($(date +%s) - START_TIME))
    echo "[Runtime: $(format_duration $ELAPSED)] $line"

    # Log SUM lines
    if echo "$line" | grep -q "\[SUM\]"; then
        SPEED=$(echo "$line" | grep -oE '[0-9.]+ [GMK]?bits/sec' | tail -1)
        if [ -n "$SPEED" ]; then
            echo "[$(format_duration $ELAPSED)] $SPEED" >> "$LOGFILE"

            # Check for zero speed (outage)
            if echo "$SPEED" | grep -qE "^0\.00 "; then
                ZERO_COUNT=$((ZERO_COUNT + 1))
                if [ $ZERO_COUNT -ge 2 ]; then
                    kill "$IPERF_PID" 2>/dev/null
                    wait "$IPERF_PID" 2>/dev/null
                    trap - EXIT
                    log_exit "Stopping due to internet outage (zero speed detected)."
                    exit 1
                fi
            else
                ZERO_COUNT=0
            fi
        fi
    fi

    # Check for error messages
    if echo "$line" | grep -qiE "(error|unable to connect|connection refused|no route|network is unreachable|broken pipe)"; then
        kill "$IPERF_PID" 2>/dev/null
        wait "$IPERF_PID" 2>/dev/null
        trap - EXIT
        log_exit "Stopping due to connection error."
        exit 1
    fi
done < "$FIFO"

wait "$IPERF_PID"
EXIT_CODE=$?

trap - EXIT
if [ $EXIT_CODE -ne 0 ]; then
    log_exit "Connection failed (exit code: $EXIT_CODE)"
    exit $EXIT_CODE
fi
