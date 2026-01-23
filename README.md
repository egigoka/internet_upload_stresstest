# internet_upload_stresstest

Saturate your upload bandwidth using iperf3 with automatic outage detection.

## Requirements

- `iperf3` installed on both client and server

```bash
# Debian/Ubuntu
sudo apt install iperf3

# Fedora/RHEL
sudo dnf install iperf3

# macOS
brew install iperf3
```

## Usage

### Server

Run on the machine that will receive the upload traffic:

```bash
./server.sh [port]
```

- `port` - Server port (default: 5201)

Example:
```bash
./server.sh 5201
```

### Client Scripts

Three client variants are available depending on your needs. All clients:
- Log speed and runtime every 10 seconds
- Use 8 parallel streams to maximize bandwidth saturation
- Create timestamped log files
- Show total runtime on exit

#### client-once.sh - Single run until outage

Runs one continuous upload test and stops when connection fails:

```bash
./client-once.sh <server_ip> [port]
```

- `server_ip` - Server IP address or hostname (required)
- `port` - Server port (default: 5201)

Example:
```bash
./client-once.sh 192.168.1.100
```

Best for: Testing how long your connection stays stable.

#### client-infinite.sh - Retry forever

Runs upload tests continuously, automatically retrying after outages:

```bash
./client-infinite.sh <server_ip> [port]
```

- `server_ip` - Server IP address or hostname (required)
- `port` - Server port (default: 5201)

Example:
```bash
./client-infinite.sh 192.168.1.100
```

Best for: Long-term stress testing with automatic recovery.

#### client-until.sh - Run until specific time

Runs upload tests until a specified time, with automatic retry on outages:

```bash
./client-until.sh <server_ip> <stop_time> [port]
```

- `server_ip` - Server IP address or hostname (required)
- `stop_time` - Time to stop in HH:MM format (e.g., 23:00 or 6:00)
- `port` - Server port (default: 5201)

Examples:
```bash
./client-until.sh 192.168.1.100 23:00      # Run until 11 PM
./client-until.sh 192.168.1.100 6:00 5201  # Run until 6 AM on custom port
```

Best for: Scheduled testing windows (e.g., run overnight until morning).

## Notes

- More parallel streams (`-P`) generally means better saturation
- The client stops immediately on connection failure
- Press Ctrl+C to stop manually
