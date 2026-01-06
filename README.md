# seedlink-relay

Rebroadcast remote SeedLink data to local clients.

## Overview

This repository provides a complete SeedLink relay solution:

- **slink2dali**: Pulls data from remote SeedLink server(s) and converts to DataLink
- **ringserver**: Receives DataLink data and rebroadcasts via SeedLink
- **slinktool**: Included for testing and querying SeedLink servers

All components are built from source and run in a single container with multiple processes.

## Quick Start

1. **Create source scripts:**

   Copy the example template and customize for your sources:

   ```bash
   cp config/slink2dali-source-example.sh.example config/slink2dali-source-<name>.sh
   # Edit the script with your source details
   chmod +x config/slink2dali-source-<name>.sh
   ```

   The entrypoint automatically finds and runs all executable `slink2dali-source-*.sh` files.

   **Note:** State files (`slink2dali-*.state`) are created automatically by `slink2dali` at runtime. You can optionally create initial state files by copying `config/slink2dali-example.state.example` to `config/slink2dali-<name>.state`.

2. **Start the relay:**

   ```bash
   docker compose up -d
   ```

3. **Clients connect to:**

   ```bash
   localhost:18000
   ```

   **Note for external containers:** If connecting from another Docker container, use one of:

   - `--network host` flag: `docker run --rm --network host ghcr.io/platformfuzz/slinktool-image:latest -Q 127.0.0.1:18000`
   - Host's IP address instead of `127.0.0.1`
   - Connect from the host directly (not from a container)

4. **Test the relay:**

   The image includes `slinktool` for testing. Query the relay from within the container:

   ```bash
   docker exec seedlink-relay slinktool -Q localhost:18000
   ```

   Or test from the host (if using host networking or proper port mapping):

   ```bash
   docker exec seedlink-relay slinktool -Q 127.0.0.1:18000
   ```

## Configuration

### Per-Source Shell Scripts

Create individual shell scripts for each source in the `config/` directory. Start by copying the example template:

```bash
cp config/slink2dali-source-example.sh.example config/slink2dali-source-<name>.sh
chmod +x config/slink2dali-source-<name>.sh
```

The entrypoint automatically finds and executes all executable files matching `slink2dali-source-*.sh`.

Each source will run as a separate `slink2dali` process, all feeding into the same `ringserver` instance.

**Example script structure:**

```bash
#!/bin/sh
slink2dali -N <NETWORK> -x /config/slink2dali-<name>.state -nt 300 -s "<STREAM_SELECTOR>" -S "<STATION_SELECTOR>" <seedlink_host>:<port> localhost:16000
```

**slink2dali arguments:**

- `-N`: Network code (e.g., `NZ`, `US`, `IU`)
- `-x`: State file path (must be in `/config/` directory, e.g., `/config/slink2dali-<name>.state`)
- `-nt`: Network timeout in seconds (e.g., `300`)
- `-s`: Stream selector (e.g., `"CRX EH? HH? LH?"`)
- `-S`: Station selector (e.g., `"NZ_*"`, `"US_*"`)
- Last two arguments: source SeedLink server and destination DataLink server (e.g., `sl-primary.example.org:18000 localhost:16000`)

**State Files:**

State files are automatically created by `slink2dali` at runtime in the `/config/` directory. They track the last processed sequence number and timestamp for resumption after restarts. You can optionally create an initial state file by copying the example:

```bash
cp config/slink2dali-example.state.example config/slink2dali-<name>.state
# Edit with your network code and initial timestamp
```

**Note:** All sources feed into the same `ringserver` DataLink port (16000), and each source maintains its own state file for resumption.

## Architecture

```text
Remote SeedLink Server
    ↓
slink2dali (SeedLink → DataLink converter)
    ↓
ringserver DataLink (port 16000)
    ↓
Ring Buffer
    ↓
ringserver SeedLink (port 18000)
    ↓
Local Clients
```

## Ports

- **18000**: SeedLink server (clients connect here)
- **16000**: DataLink server (internal, receives from slink2dali)

## Volumes

- `ringserver-data`: Persistent ring buffer storage (mounted at `/data`)
- `./config`: Configuration directory (mounted at `/config`)
  - `ringserver.conf`: Ringserver configuration file
  - `slink2dali-source-*.sh`: Source scripts (executable shell scripts)
  - `slink2dali-*.state`: State files (auto-generated, persisted for resumption)

## AWS ECS Deployment

This setup works well in ECS with the following considerations:

### Network Mode: `awsvpc` (Recommended)

When deployed to ECS with `awsvpc` network mode (default for Fargate):

- **Internal communication**: `slink2dali` connects to `ringserver` via `localhost:16000` - this works because both processes run in the same container
- **External access**: Clients connect via:
  - **Service discovery DNS name**: `seedlink-relay.<namespace>:18000` (if using ECS service discovery)
  - **Task IP address**: Direct connection to the task's private IP on port 18000
  - **Load balancer**: If using an ALB/NLB, connect via the load balancer DNS name

### Key Points

1. **No `127.0.0.1` issues**: The `127.0.0.1` limitation only affects local Docker testing. In ECS, services use proper IPs or service discovery.

2. **Port mapping**: The container exposes ports 18000 (SeedLink) and 16000 (DataLink). In ECS, these are automatically mapped to the task's network interface.

3. **Health checks**: The health check uses `localhost:18000` which works fine within the container.

4. **Service discovery**: Configure ECS service discovery to allow other services to connect via DNS name instead of IP addresses.

### Example ECS Task Definition Snippet

```json
{
  "networkMode": "awsvpc",
  "containerDefinitions": [
    {
      "name": "seedlink-relay",
      "image": "your-registry/seedlink-relay:latest",
      "portMappings": [
        {
          "containerPort": 18000,
          "protocol": "tcp"
        },
        {
          "containerPort": 16000,
          "protocol": "tcp"
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "config",
          "containerPath": "/config",
          "readOnly": false
        }
      ]
    }
  ],
  "volumes": [
    {
      "name": "config",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-xxxxx",
        "rootDirectory": "/config"
      }
    }
  ]
}
```

**Note:** Source scripts must be provided via a mounted volume (EFS, EBS, or bind mount) at `/config/slink2dali-source-*.sh`. State files will be persisted in the same volume.

## License

MIT License - see LICENSE file for details.
