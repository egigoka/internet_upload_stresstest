#!/bin/bash
# iperf3 server wrapper

PORT=${1:-5201}

echo "Starting iperf3 server on port $PORT..."
echo "Press Ctrl+C to stop"
echo ""

iperf3 -s -p "$PORT"
