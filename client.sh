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

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

echo "Upload stress test to $SERVER:$PORT with $PARALLEL parallel streams"
echo "Reporting every $INTERVAL seconds"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Starting iperf3 test..."

    iperf3 -c "$SERVER" -p "$PORT" -P "$PARALLEL" -t 0 -i "$INTERVAL" --forceflush 2>&1 | while read -r line; do
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "[Runtime: $(format_duration $ELAPSED)] $line"
    done
    EXIT_CODE=${PIPESTATUS[0]}

    if [ $EXIT_CODE -ne 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Runtime: $(format_duration $ELAPSED)] Connection failed (exit code: $EXIT_CODE)"
        echo "Stopping due to internet outage."
        echo "Total runtime: $(format_duration $ELAPSED)"
        exit $EXIT_CODE
    fi
done
