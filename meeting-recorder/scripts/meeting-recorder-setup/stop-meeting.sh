#!/bin/bash
# Stop Meeting - Leave the current meeting and cleanup
#
# Usage: stop-meeting.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOME/.meeting-recorder.json"
MEETINGS_DIR="/tmp/meetings"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        MEETINGS_DIR=$(jq -r '.meetings_dir // "/tmp/meetings"' "$CONFIG_FILE")
    fi
}

# Get current meeting ID
get_current_meeting() {
    if [ -L "$MEETINGS_DIR/current" ]; then
        basename "$(readlink -f "$MEETINGS_DIR/current")"
    else
        echo ""
    fi
}

# Stop transcription process
stop_transcription() {
    echo "Stopping transcription..."

    if [ -f /tmp/meeting_transcriber.pid ]; then
        local pid=$(cat /tmp/meeting_transcriber.pid)
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            # Wait for graceful shutdown
            for i in {1..5}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still running
            kill -9 "$pid" 2>/dev/null || true
            echo "Transcription stopped"
        else
            echo "Transcription was not running"
        fi
        rm -f /tmp/meeting_transcriber.pid
    else
        echo "No transcription PID file found"
    fi

    # Also kill any orphaned processes
    pkill -f "meeting-transcriber.py" 2>/dev/null || true
    pkill -f "audio-capture.sh" 2>/dev/null || true
    pkill -f "parecord.*meeting_capture" 2>/dev/null || true
}

# Leave the meeting in Chrome
leave_meeting() {
    echo "Leaving meeting..."

    # Check if chrome-a11y is available
    if ! command -v chrome-a11y &> /dev/null; then
        echo -e "${YELLOW}Warning: chrome-a11y not found, cannot click Leave button${NC}"
        return 1
    fi

    # Check if Chrome is running
    if ! pgrep -f "chrome.*no-sandbox" > /dev/null; then
        echo -e "${YELLOW}Warning: Chrome not running${NC}"
        return 1
    fi

    # Try to click "Leave call" button
    if chrome-a11y list 2>/dev/null | grep -qi "leave call"; then
        chrome-a11y click "Leave call"
        sleep 2
        echo -e "${GREEN}Left the meeting${NC}"
        return 0
    else
        echo -e "${YELLOW}Could not find 'Leave call' button${NC}"
        echo "You may not be in a meeting or need to leave manually"
        return 1
    fi
}

# Cleanup PulseAudio virtual sink
cleanup_audio() {
    echo "Cleaning up audio..."

    # Get the module ID if we saved it
    if [ -f /tmp/meeting_sink_module_id ]; then
        local module_id=$(cat /tmp/meeting_sink_module_id)
        pactl unload-module "$module_id" 2>/dev/null || true
        rm -f /tmp/meeting_sink_module_id
    fi

    # Also try to unload by name
    pactl unload-module module-null-sink 2>/dev/null || true

    echo "Audio cleanup complete"
}

# Update metadata to mark meeting as ended
update_metadata() {
    local meeting_id="$1"

    if [ -z "$meeting_id" ]; then
        return
    fi

    local metadata_file="$MEETINGS_DIR/$meeting_id/metadata.json"

    if [ -f "$metadata_file" ]; then
        # Update ended_at and status
        local tmp_file=$(mktemp)
        jq --arg ended "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.ended_at = $ended | .status = "ended"' \
           "$metadata_file" > "$tmp_file" && mv "$tmp_file" "$metadata_file"
        echo "Updated metadata for meeting: $meeting_id"
    fi
}

# Remove current symlink
remove_current_link() {
    local current_link="$MEETINGS_DIR/current"
    if [ -L "$current_link" ]; then
        rm -f "$current_link"
        echo "Removed 'current' symlink"
    fi
}

# Main
main() {
    load_config

    local meeting_id=$(get_current_meeting)

    if [ -z "$meeting_id" ]; then
        echo -e "${YELLOW}No active meeting detected${NC}"
    else
        echo "Ending meeting: $meeting_id"
    fi

    echo ""

    # Stop transcription first
    stop_transcription

    # Leave the meeting
    leave_meeting || true

    # Cleanup audio
    cleanup_audio

    # Update metadata
    if [ -n "$meeting_id" ]; then
        update_metadata "$meeting_id"
    fi

    # Remove current symlink
    remove_current_link

    echo ""
    echo -e "${GREEN}Meeting ended${NC}"

    if [ -n "$meeting_id" ]; then
        echo ""
        echo "Transcript saved at: $MEETINGS_DIR/$meeting_id/transcript.txt"
        echo "View with: cat $MEETINGS_DIR/$meeting_id/transcript.txt"
    fi
}

main "$@"
