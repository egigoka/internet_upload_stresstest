#!/bin/bash
# iperf3 upload stress test client - runs forever, retries on outage

SERVER=${1:-""}
PORT=${2:-5201}
PARALLEL=8
INTERVAL=10
RETRY_DELAY=5

if [ -z "$SERVER" ]; then
    echo "Usage: $0 <server_ip> [port]"
    echo ""
    echo "Example: $0 192.168.1.100"
    exit 1
fi

START_TIME=$(date +%s)
LOGFILE="$(date '+%Y-%m-%d_%H-%M-%S').log"
IPERF_PID=""

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

cleanup() {
    if [ -n "$IPERF_PID" ] && kill -0 "$IPERF_PID" 2>/dev/null; then
        kill "$IPERF_PID" 2>/dev/null
    fi
    ELAPSED=$(($(date +%s) - START_TIME))
    echo ""
    echo "Stopped by user."
    echo "Total runtime: $(format_duration $ELAPSED)"
    echo "---" >> "$LOGFILE"
    echo "Ended: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
    echo "Reason: Stopped by user." >> "$LOGFILE"
    echo "Total runtime: $(format_duration $ELAPSED)" >> "$LOGFILE"
    rm -f "$FIFO" 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Upload stress test to $SERVER:$PORT with $PARALLEL parallel streams"
echo "Reporting every $INTERVAL seconds"
echo "Logging to: $LOGFILE"
echo "Retries on outage every $RETRY_DELAY seconds"
echo "Press Ctrl+C to stop"
echo ""

echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
echo "Server: $SERVER:$PORT" >> "$LOGFILE"
echo "---" >> "$LOGFILE"

while true; do
    FIFO=$(mktemp -u)
    mkfifo "$FIFO"
    ZERO_COUNT=0

    ELAPSED=$(($(date +%s) - START_TIME))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Starting iperf3 test..."

    iperf3 -c "$SERVER" -p "$PORT" -P "$PARALLEL" -t 0 -i "$INTERVAL" --forceflush > "$FIFO" 2>&1 &
    IPERF_PID=$!

    SHOULD_RETRY=false

    while read -r line; do
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "[Runtime: $(format_duration $ELAPSED)] $line"

        if echo "$line" | grep -q "\[SUM\]"; then
            SPEED=$(echo "$line" | grep -oE '[0-9.]+ [GMK]?bits/sec' | tail -1)
            if [ -n "$SPEED" ]; then
                echo "[$(format_duration $ELAPSED)] $SPEED" >> "$LOGFILE"

                if echo "$SPEED" | grep -qE "^0\.00 "; then
                    ZERO_COUNT=$((ZERO_COUNT + 1))
                    if [ $ZERO_COUNT -ge 2 ]; then
                        kill "$IPERF_PID" 2>/dev/null
                        wait "$IPERF_PID" 2>/dev/null
                        SHOULD_RETRY=true
                        echo "[$(format_duration $ELAPSED)] OUTAGE DETECTED" >> "$LOGFILE"
                        break
                    fi
                else
                    ZERO_COUNT=0
                fi
            fi
        fi

        if echo "$line" | grep -qiE "(error|unable to connect|connection refused|no route|network is unreachable|broken pipe)"; then
            kill "$IPERF_PID" 2>/dev/null
            wait "$IPERF_PID" 2>/dev/null
            SHOULD_RETRY=true
            echo "[$(format_duration $ELAPSED)] CONNECTION ERROR" >> "$LOGFILE"
            break
        fi
    done < "$FIFO"

    rm -f "$FIFO"

    if [ "$SHOULD_RETRY" = true ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Connection lost. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    else
        wait "$IPERF_PID" 2>/dev/null
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] iperf3 exited. Restarting..."
    fi
done
