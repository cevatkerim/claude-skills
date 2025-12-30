#!/bin/bash
#
# Stop Chrome Automation Services
#

VNC_DISPLAY=":1"
NOVNC_PORT="6080"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

log_info "Stopping Chrome Automation services..."

# Stop Chrome Monitor daemon
if [ -f /tmp/chrome-monitor.pid ]; then
    kill $(cat /tmp/chrome-monitor.pid) 2>/dev/null && log_info "Chrome Monitor stopped"
    rm -f /tmp/chrome-monitor.pid
fi

# Stop Chrome
pkill -9 chrome 2>/dev/null && log_info "Chrome stopped"

# Stop noVNC/websockify
pkill -f "websockify.*$NOVNC_PORT" 2>/dev/null && log_info "noVNC stopped"

# Stop VNC server
vncserver -kill $VNC_DISPLAY 2>/dev/null && log_info "VNC server stopped"

log_info "All services stopped"
