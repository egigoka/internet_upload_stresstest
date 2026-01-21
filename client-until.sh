#!/bin/bash
# iperf3 upload stress test client - runs until specified time

SERVER=${1:-""}
STOP_TIME=${2:-""}
PORT=${3:-5201}
PARALLEL=8
INTERVAL=10

if [ -z "$SERVER" ] || [ -z "$STOP_TIME" ]; then
    echo "Usage: $0 <server_ip> <stop_time> [port]"
    echo ""
    echo "Arguments:"
    echo "  stop_time   Time to stop (HH:MM format, e.g. 23:00 or 6:00)"
    echo ""
    echo "Example: $0 192.168.1.100 23:00"
    exit 1
fi

# Validate time format
if ! echo "$STOP_TIME" | grep -qE "^[0-9]{1,2}:[0-9]{2}$"; then
    echo "Error: Invalid time format. Use HH:MM (e.g. 23:00 or 6:00)"
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

time_reached() {
    local current=$(date '+%H:%M')
    [ "$current" = "$STOP_TIME" ] || [ "$current" \> "$STOP_TIME" -a "$LAST_CHECK" \< "$STOP_TIME" ]
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

stop_at_time() {
    if [ -n "$IPERF_PID" ] && kill -0 "$IPERF_PID" 2>/dev/null; then
        kill "$IPERF_PID" 2>/dev/null
    fi
    ELAPSED=$(($(date +%s) - START_TIME))
    echo ""
    echo "Stop time $STOP_TIME reached."
    echo "Total runtime: $(format_duration $ELAPSED)"
    echo "---" >> "$LOGFILE"
    echo "Ended: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
    echo "Reason: Stop time $STOP_TIME reached." >> "$LOGFILE"
    echo "Total runtime: $(format_duration $ELAPSED)" >> "$LOGFILE"
    rm -f "$FIFO" 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Upload stress test to $SERVER:$PORT with $PARALLEL parallel streams"
echo "Reporting every $INTERVAL seconds"
echo "Logging to: $LOGFILE"
echo "Will stop at: $STOP_TIME"
echo "Press Ctrl+C to stop"
echo ""

echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
echo "Server: $SERVER:$PORT" >> "$LOGFILE"
echo "Stop time: $STOP_TIME" >> "$LOGFILE"
echo "---" >> "$LOGFILE"

LAST_CHECK=$(date '+%H:%M')

while true; do
    # Check if stop time reached
    CURRENT_TIME=$(date '+%H:%M')
    if [ "$CURRENT_TIME" = "$STOP_TIME" ]; then
        stop_at_time
    fi
    # Handle day wrap (e.g., started at 23:30, stop at 01:00)
    if [ "$LAST_CHECK" \> "$CURRENT_TIME" ] && [ "$STOP_TIME" \< "$CURRENT_TIME" -o "$STOP_TIME" \> "$LAST_CHECK" ]; then
        stop_at_time
    fi
    LAST_CHECK=$CURRENT_TIME

    FIFO=$(mktemp -u)
    mkfifo "$FIFO"
    ZERO_COUNT=0

    ELAPSED=$(($(date +%s) - START_TIME))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Starting iperf3 test..."

    iperf3 -c "$SERVER" -p "$PORT" -P "$PARALLEL" -t 0 -i "$INTERVAL" --forceflush > "$FIFO" 2>&1 &
    IPERF_PID=$!

    SHOULD_RETRY=false

    while read -r line; do
        # Check stop time
        CURRENT_TIME=$(date '+%H:%M')
        if [ "$CURRENT_TIME" = "$STOP_TIME" ]; then
            kill "$IPERF_PID" 2>/dev/null
            wait "$IPERF_PID" 2>/dev/null
            rm -f "$FIFO"
            stop_at_time
        fi

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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Connection lost. Retrying in 5 seconds..."
        sleep 5
    else
        wait "$IPERF_PID" 2>/dev/null
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] iperf3 exited. Restarting..."
    fi
done
