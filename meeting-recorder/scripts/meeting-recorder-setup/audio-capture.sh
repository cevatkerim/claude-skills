#!/bin/bash
# Audio Capture Helper
# Creates PulseAudio virtual sink and captures audio from it

set -e

SAMPLE_RATE="${1:-24000}"
CHANNELS="${2:-1}"
FORMAT="${3:-s16le}"
SINK_NAME="meeting_capture"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Function to cleanup on exit
cleanup() {
    # Don't unload the sink here - let stop-meeting.sh handle it
    exit 0
}

trap cleanup EXIT INT TERM

# Ensure PulseAudio is running
if ! pulseaudio --check 2>/dev/null; then
    echo "Starting PulseAudio..." >&2
    pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
    sleep 1
fi

# Check if virtual sink exists, create if not
if ! pactl list sinks short 2>/dev/null | grep -q "$SINK_NAME"; then
    echo "Creating virtual audio sink: $SINK_NAME" >&2
    pactl load-module module-null-sink \
        sink_name="$SINK_NAME" \
        sink_properties=device.description="Meeting_Audio_Capture" \
        > /tmp/meeting_sink_module_id 2>/dev/null

    # Small delay for sink to be ready
    sleep 0.5
fi

# Set as default sink so Chrome uses it
pactl set-default-sink "$SINK_NAME" 2>/dev/null || true

echo "Audio capture started (rate=${SAMPLE_RATE}, channels=${CHANNELS}, format=${FORMAT})" >&2
echo "Capturing from: ${SINK_NAME}.monitor" >&2

# Start recording from the monitor source
# This captures what goes INTO the sink (i.e., Chrome's audio output)
exec parecord \
    -d "${SINK_NAME}.monitor" \
    --raw \
    --rate="$SAMPLE_RATE" \
    --channels="$CHANNELS" \
    --format="$FORMAT"
