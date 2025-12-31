#!/bin/bash
# Meeting Recorder - Main entry point
# Join Google Meet calls, transcribe audio, and participate via chat

set -e

# Resolve symlinks to get actual script location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SETUP_DIR="$SCRIPT_DIR/meeting-recorder-setup"
MEETINGS_DIR="${MEETINGS_DIR:-/tmp/meetings}"
CONFIG_FILE="$HOME/.meeting-recorder.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load config
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

# Show help
show_help() {
    cat << 'EOF'
Meeting Recorder - Join Google Meet calls with real-time transcription

USAGE:
    meeting-recorder <command> [arguments]

COMMANDS:
    join <url> [name]     Join a Google Meet and start transcription
    leave                 Leave the current meeting
    chat <message>        Send a message to the meeting chat
    status                Show current meeting status
    transcript [id]       Display transcript (current meeting if no ID)
    chat-history          Read chat messages from Google Meet
    setup                 Run initial setup (installs dependencies)
    help                  Show this help message

EXAMPLES:
    meeting-recorder join "https://meet.google.com/abc-defg-hij"
    meeting-recorder join "https://meet.google.com/abc-defg-hij" "My Bot"
    meeting-recorder chat "Hello everyone!"
    meeting-recorder transcript
    meeting-recorder leave

MEETING FILES:
    Transcripts are stored at /tmp/meetings/<meeting-id>/
    - transcript.txt    Full transcript with timestamps
    - metadata.json     Meeting info (URL, start time, status)
    - mentions.txt      Detected questions/mentions
    - chat.json         Chat messages from Google Meet

    /tmp/meetings/current -> symlink to active meeting

CONFIGURATION:
    Edit ~/.meeting-recorder.json to customize:
    - participant_name   Name shown in meeting
    - mention_keywords   Words to detect for alerts
    - transcription_model   Whisper model to use

For detailed documentation, see REFERENCE.md
EOF
}

# Join command
cmd_join() {
    local url="$1"
    local name="${2:-}"

    if [ -z "$url" ]; then
        echo -e "${RED}Error: Meeting URL required${NC}"
        echo "Usage: meeting-recorder join <url> [name]"
        exit 1
    fi

    "$SETUP_DIR/start-meeting.sh" "$url" "$name"
}

# Leave command
cmd_leave() {
    "$SETUP_DIR/stop-meeting.sh"
}

# Chat command
cmd_chat() {
    local message="$1"

    if [ -z "$message" ]; then
        echo -e "${RED}Error: Message required${NC}"
        echo "Usage: meeting-recorder chat <message>"
        exit 1
    fi

    "$SETUP_DIR/send-chat.sh" "$message"
}

# Status command
cmd_status() {
    local meeting_id=$(get_current_meeting)

    if [ -z "$meeting_id" ]; then
        echo "Not currently in a meeting"

        # List recent meetings
        if [ -d "$MEETINGS_DIR" ] && [ "$(ls -A "$MEETINGS_DIR" 2>/dev/null)" ]; then
            echo ""
            echo "Recent meetings:"
            ls -lt "$MEETINGS_DIR" | head -6 | tail -5
        fi
        return 0
    fi

    local metadata="$MEETINGS_DIR/$meeting_id/metadata.json"
    local transcript="$MEETINGS_DIR/$meeting_id/transcript.txt"

    echo -e "${GREEN}Meeting in progress: $meeting_id${NC}"

    if [ -f "$metadata" ]; then
        local started_at=$(jq -r '.started_at' "$metadata")
        local participant=$(jq -r '.participant_name' "$metadata")
        echo "Participant: $participant"
        echo "Started: $started_at"
    fi

    if [ -f "$transcript" ]; then
        local lines=$(wc -l < "$transcript")
        echo "Transcript lines: $lines"
    fi

    # Check if transcriber is running
    if [ -f "/tmp/meeting_transcriber.pid" ]; then
        local pid=$(cat /tmp/meeting_transcriber.pid)
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Transcriber: ${GREEN}running${NC} (PID $pid)"
        else
            echo -e "Transcriber: ${RED}stopped${NC}"
        fi
    fi
}

# Transcript command
cmd_transcript() {
    local meeting_id="${1:-$(get_current_meeting)}"

    if [ -z "$meeting_id" ]; then
        echo -e "${RED}Error: No active meeting and no meeting ID provided${NC}"
        echo "Usage: meeting-recorder transcript [meeting_id]"
        exit 1
    fi

    local transcript="$MEETINGS_DIR/$meeting_id/transcript.txt"

    if [ ! -f "$transcript" ]; then
        echo -e "${RED}Error: Transcript not found: $transcript${NC}"
        exit 1
    fi

    cat "$transcript"
}

# Chat history command (using the JS snippet)
cmd_chat_history() {
    local meeting_id=$(get_current_meeting)

    if [ -z "$meeting_id" ]; then
        echo -e "${RED}Error: Not currently in a meeting${NC}"
        exit 1
    fi

    "$SETUP_DIR/read-chat.sh"
}

# Setup command
cmd_setup() {
    "$SETUP_DIR/setup.sh"
}

# Main
load_config

case "${1:-}" in
    join)
        cmd_join "$2" "$3"
        ;;
    leave)
        cmd_leave
        ;;
    chat)
        shift
        cmd_chat "$*"
        ;;
    status)
        cmd_status
        ;;
    transcript)
        cmd_transcript "$2"
        ;;
    chat-history)
        cmd_chat_history
        ;;
    setup)
        cmd_setup
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run 'meeting-recorder help' for usage"
        exit 1
        ;;
esac
