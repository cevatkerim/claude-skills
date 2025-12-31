#!/bin/bash
# Send Chat Message to Google Meet
#
# Usage: send-chat.sh "message to send"

set -e

MESSAGE="$1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$MESSAGE" ]; then
    echo -e "${RED}Error: Message required${NC}"
    echo "Usage: send-chat.sh 'message to send'"
    exit 1
fi

# Check if chrome-a11y is available
if ! command -v chrome-a11y &> /dev/null; then
    echo -e "${RED}Error: chrome-a11y not found${NC}"
    exit 1
fi

# Check if Chrome is running
if ! pgrep -f "chrome.*no-sandbox" > /dev/null; then
    echo -e "${RED}Error: Chrome not running${NC}"
    exit 1
fi

# Check if we're in a meeting
if ! chrome-a11y list 2>/dev/null | grep -qi "leave call"; then
    echo -e "${RED}Error: Not currently in a meeting${NC}"
    exit 1
fi

echo "Sending chat message..."

# First, make sure chat panel is open
# Try to find "Send a message" input which indicates chat is open
if ! chrome-a11y list 2>/dev/null | grep -qi "send a message"; then
    # Chat panel might be closed, try to open it
    echo "Opening chat panel..."

    # Try various button names for the chat button
    if chrome-a11y list 2>/dev/null | grep -qi "chat with everyone"; then
        chrome-a11y click "Chat with everyone"
        sleep 1
    elif chrome-a11y list 2>/dev/null | grep -qi "show chat"; then
        chrome-a11y click "Show chat"
        sleep 1
    elif chrome-a11y list 2>/dev/null | grep -qi "chat"; then
        chrome-a11y click "Chat"
        sleep 1
    else
        echo -e "${YELLOW}Warning: Could not find chat button${NC}"
        echo "Available elements:"
        chrome-a11y list 2>/dev/null | head -20
    fi
fi

# Now try to find and click the message input
if chrome-a11y list 2>/dev/null | grep -qi "send a message"; then
    chrome-a11y click "Send a message to everyone" 2>/dev/null || \
    chrome-a11y click "Send a message" 2>/dev/null || true
    sleep 0.3
else
    echo -e "${YELLOW}Warning: Could not find message input${NC}"
fi

# Type the message
chrome-a11y type "$MESSAGE"
sleep 0.2

# Send by pressing Enter
chrome-a11y key "Return"

echo -e "${GREEN}Message sent: $MESSAGE${NC}"
