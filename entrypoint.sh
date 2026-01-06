#!/bin/sh

# Validate required directories exist
if [ ! -d "/data" ]; then
    echo "ERROR: /data directory does not exist" >&2
    exit 2
fi

if [ ! -d "/config" ]; then
    echo "ERROR: /config directory does not exist" >&2
    exit 2
fi

CONFIG_FILE="/config/ringserver.conf"

# Validate config file exists and is readable
if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE does not exist or is not readable" >&2
    exit 1
fi

# Start ringserver in background
echo "Starting ringserver with config: $CONFIG_FILE" >&2
/usr/local/bin/ringserver "$CONFIG_FILE" &
RINGSERVER_PID=$!

# Wait for ringserver to be ready
sleep 3

# Start slink2dali instances from source scripts
echo "Loading source scripts from /config/slink2dali-source-*.sh" >&2
# Ensure state files are writable
chmod 666 /config/slink2dali-*.state 2>/dev/null || true
for source_script in /config/slink2dali-source-*.sh; do
    if [ -f "$source_script" ] && [ -x "$source_script" ]; then
        name=$(basename "$source_script" .sh | sed 's/slink2dali-source-//')
        echo "Starting slink2dali [$name]" >&2
        "$source_script" &
    fi
done

# Wait for ringserver (main process)
wait $RINGSERVER_PID
