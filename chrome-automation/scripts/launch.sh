#!/bin/bash
#
# Chrome Automation Launcher
# Launches Chrome with accessibility features for AT-SPI2 control
#
# Usage:
#   launch.sh [URL]           Launch Chrome (or report if already running)
#   launch.sh status          Check if Chrome is running
#   launch.sh stop            Stop Chrome
#   launch.sh restart [URL]   Restart Chrome
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if Chrome is running
is_chrome_running() {
    pgrep -f "chrome.*no-sandbox" > /dev/null 2>&1
}

# Get Chrome PID
get_chrome_pid() {
    pgrep -f "chrome.*no-sandbox" | head -1
}

# Status check
status() {
    if is_chrome_running; then
        local pid=$(get_chrome_pid)
        echo -e "${GREEN}Chrome is running${NC} (PID: $pid)"
        return 0
    else
        echo -e "${RED}Chrome is not running${NC}"
        return 1
    fi
}

# Stop Chrome
stop_chrome() {
    if is_chrome_running; then
        echo "Stopping Chrome..."
        pkill -9 chrome 2>/dev/null
        sleep 2
        if is_chrome_running; then
            echo -e "${RED}Failed to stop Chrome${NC}"
            return 1
        else
            echo -e "${GREEN}Chrome stopped${NC}"
            return 0
        fi
    else
        echo "Chrome is not running"
        return 0
    fi
}

# Launch Chrome
launch_chrome() {
    local url="${1:-about:blank}"

    # Check if already running
    if is_chrome_running; then
        local pid=$(get_chrome_pid)
        echo -e "${YELLOW}Chrome is already running${NC} (PID: $pid)"
        echo "Use 'launch.sh restart [URL]' to restart, or 'launch.sh stop' to stop"
        return 0
    fi

    echo "Launching Chrome..."

    # Set environment
    export DISPLAY=:1
    export GTK_MODULES=gail:atk-bridge
    export NO_AT_BRIDGE=0
    export GNOME_ACCESSIBILITY=1

    # Launch Chrome
    google-chrome \
        --no-sandbox \
        --disable-gpu \
        --start-maximized \
        --force-renderer-accessibility \
        --no-first-run \
        --disable-background-networking \
        "$url" &

    # Wait for startup
    sleep 4

    # Verify
    if is_chrome_running; then
        local pid=$(get_chrome_pid)
        echo -e "${GREEN}Chrome launched successfully${NC} (PID: $pid)"
        echo ""
        echo "Control with:"
        echo "  chrome-a11y list              # List clickable elements"
        echo "  chrome-a11y click 'Button'    # Click element"
        echo "  chrome-a11y navigate 'URL'    # Go to URL"
        return 0
    else
        echo -e "${RED}Failed to launch Chrome${NC}"
        return 1
    fi
}

# Main
case "${1:-}" in
    status)
        status
        ;;
    stop)
        stop_chrome
        ;;
    restart)
        stop_chrome
        sleep 1
        launch_chrome "${2:-about:blank}"
        ;;
    help|--help|-h)
        echo "Chrome Automation Launcher"
        echo ""
        echo "Usage:"
        echo "  launch.sh [URL]         Launch Chrome (checks if already running)"
        echo "  launch.sh status        Check if Chrome is running"
        echo "  launch.sh stop          Stop Chrome"
        echo "  launch.sh restart [URL] Restart Chrome"
        echo "  launch.sh help          Show this help"
        ;;
    *)
        launch_chrome "$1"
        ;;
esac
