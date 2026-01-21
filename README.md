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

Default port: 5201

### Client

Run on the machine whose upload you want to stress test:

```bash
./client.sh <server_ip> [port]
```

- `server_ip` - Server IP address or hostname (required)
- `port` - Server port (default: 5201)

Example:
```bash
./client.sh 192.168.1.100
```

The client will:
- Run continuous upload tests indefinitely
- Log speed and runtime every 10 seconds
- Use 8 parallel streams to maximize bandwidth saturation
- Automatically stop when connection fails (internet outage)
- Show total runtime on exit

## Notes

- More parallel streams (`-P`) generally means better saturation
- The client stops immediately on connection failure
- Press Ctrl+C to stop manually
