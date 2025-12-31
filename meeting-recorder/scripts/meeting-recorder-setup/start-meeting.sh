#!/bin/bash
# Start Meeting - Join a Google Meet and start transcription
#
# Usage: start-meeting.sh <meeting_url> [participant_name]

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
        PARTICIPANT_NAME=$(jq -r '.participant_name // "Claude Assistant"' "$CONFIG_FILE")
        MEETINGS_DIR=$(jq -r '.meetings_dir // "/tmp/meetings"' "$CONFIG_FILE")
    else
        PARTICIPANT_NAME="Claude Assistant"
    fi
}

# Extract meeting ID from URL
extract_meeting_id() {
    local url="$1"
    # Pattern: meet.google.com/xxx-yyyy-zzz
    echo "$url" | grep -oP 'meet\.google\.com/\K[a-z]{3}-[a-z]{4}-[a-z]{3}' || \
    echo "$url" | rev | cut -d'/' -f1 | rev
}

# Check prerequisites
check_prerequisites() {
    local errors=0

    # Check Chrome is running
    if ! pgrep -f "chrome.*no-sandbox" > /dev/null; then
        echo -e "${RED}Error: Chrome not running${NC}"
        echo "Start Chrome with: start-chrome-automation"
        errors=$((errors + 1))
    fi

    # Check chrome-a11y is available
    if ! command -v chrome-a11y &> /dev/null; then
        echo -e "${RED}Error: chrome-a11y not found${NC}"
        echo "Make sure chrome-automation skill is installed"
        errors=$((errors + 1))
    fi

    # Check Speaches is running
    if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Speaches not responding${NC}"
        echo "Transcription may not work. Check: docker ps | grep speaches"
    fi

    # Check PulseAudio
    if ! command -v pactl &> /dev/null; then
        echo -e "${RED}Error: PulseAudio not installed${NC}"
        echo "Run: meeting-recorder setup"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        exit 1
    fi
}

# Join the meeting using chrome-a11y
join_meeting() {
    local url="$1"
    local name="$2"

    echo "Navigating to meeting..."
    chrome-a11y navigate "$url"
    sleep 5

    # Try to dismiss common dialogs
    echo "Handling dialogs..."
    chrome-a11y click "Dismiss" 2>/dev/null || true
    chrome-a11y click "Got it" 2>/dev/null || true
    chrome-a11y click "Close" 2>/dev/null || true
    sleep 1

    # Turn off camera and microphone (we're just observing)
    echo "Disabling camera and microphone..."
    chrome-a11y click "Turn off camera" 2>/dev/null || true
    chrome-a11y click "Turn off microphone" 2>/dev/null || true
    sleep 1

    # Enter participant name
    echo "Entering participant name: $name"
    # Try to find and click the name input
    if chrome-a11y list 2>/dev/null | grep -qi "your name"; then
        chrome-a11y click "Your name" 2>/dev/null || true
        sleep 0.5
        chrome-a11y key "ctrl+a"
        chrome-a11y type "$name"
        sleep 1
    fi

    # Click join button
    echo "Attempting to join..."
    if chrome-a11y list 2>/dev/null | grep -qi "ask to join"; then
        chrome-a11y click "Ask to join"
    elif chrome-a11y list 2>/dev/null | grep -qi "join now"; then
        chrome-a11y click "Join now"
    else
        # Try generic join button
        chrome-a11y click "Join" 2>/dev/null || true
    fi

    # Wait for join confirmation
    echo "Waiting to join..."
    local joined=false
    for i in {1..60}; do
        if chrome-a11y list 2>/dev/null | grep -qi "leave call"; then
            joined=true
            break
        fi
        # Also check for "You're in a call" or meeting controls
        if chrome-a11y list 2>/dev/null | grep -qi "turn on microphone"; then
            joined=true
            break
        fi
        sleep 1
    done

    if [ "$joined" = false ]; then
        echo -e "${YELLOW}Warning: Could not confirm meeting join${NC}"
        echo "The meeting may still be joining or waiting for host approval."
        echo "Check Chrome display manually."
        return 1
    fi

    echo -e "${GREEN}Successfully joined meeting${NC}"
    return 0
}

# Start transcription
start_transcription() {
    local meeting_id="$1"
    local meeting_url="$2"

    echo "Starting audio capture and transcription..."

    # Kill any existing transcriber
    if [ -f /tmp/meeting_transcriber.pid ]; then
        local old_pid=$(cat /tmp/meeting_transcriber.pid)
        kill "$old_pid" 2>/dev/null || true
        rm -f /tmp/meeting_transcriber.pid
    fi

    # Start the audio capture and transcription pipeline
    # audio-capture.sh outputs raw PCM to stdout
    # meeting-transcriber-batch.py reads from stdin and transcribes via HTTP API
    "$SCRIPT_DIR/audio-capture.sh" 2>/dev/null | \
    python3 "$SCRIPT_DIR/meeting-transcriber-batch.py" "$meeting_id" "$meeting_url" &

    local pid=$!
    echo $pid > /tmp/meeting_transcriber.pid

    # Give it a moment to start
    sleep 2

    # Verify it's running
    if kill -0 $pid 2>/dev/null; then
        echo -e "${GREEN}Transcription started (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}Error: Transcription failed to start${NC}"
        rm -f /tmp/meeting_transcriber.pid
        return 1
    fi
}

# Main
main() {
    local meeting_url="$1"
    local custom_name="$2"

    if [ -z "$meeting_url" ]; then
        echo -e "${RED}Error: Meeting URL required${NC}"
        echo "Usage: start-meeting.sh <meeting_url> [participant_name]"
        exit 1
    fi

    # Validate URL format
    if [[ ! "$meeting_url" =~ ^https://meet\.google\.com/ ]]; then
        echo -e "${RED}Error: Invalid Google Meet URL${NC}"
        echo "Expected format: https://meet.google.com/xxx-yyyy-zzz"
        exit 1
    fi

    # Load config
    load_config

    # Use custom name if provided
    if [ -n "$custom_name" ]; then
        PARTICIPANT_NAME="$custom_name"
    fi

    # Extract meeting ID
    local meeting_id=$(extract_meeting_id "$meeting_url")
    if [ -z "$meeting_id" ]; then
        echo -e "${RED}Error: Could not extract meeting ID from URL${NC}"
        exit 1
    fi

    echo -e "${GREEN}Meeting ID: $meeting_id${NC}"
    echo "Participant: $PARTICIPANT_NAME"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Join the meeting
    if ! join_meeting "$meeting_url" "$PARTICIPANT_NAME"; then
        echo -e "${YELLOW}Continuing with transcription setup...${NC}"
    fi

    # Start transcription
    if ! start_transcription "$meeting_id" "$meeting_url"; then
        echo -e "${RED}Failed to start transcription${NC}"
        exit 1
    fi

    # Success output
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Meeting Ready${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Meeting ID: $meeting_id"
    echo "Transcript: $MEETINGS_DIR/$meeting_id/transcript.txt"
    echo "Mentions:   $MEETINGS_DIR/$meeting_id/mentions.txt"
    echo "Metadata:   $MEETINGS_DIR/$meeting_id/metadata.json"
    echo ""
    echo "Commands:"
    echo "  tail -f $MEETINGS_DIR/current/transcript.txt  # Watch transcript"
    echo "  meeting-recorder chat \"message\"              # Send chat"
    echo "  meeting-recorder leave                        # Leave meeting"
}

main "$@"
