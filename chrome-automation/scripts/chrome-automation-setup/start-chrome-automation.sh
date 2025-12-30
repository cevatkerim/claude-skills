#!/bin/bash
#
# Chrome Automation Startup Script
# Starts VNC, Chrome with accessibility, and helper services
#

set -e

# Configuration
VNC_DISPLAY=":1"
VNC_PORT="5901"
NOVNC_PORT="6080"
VNC_GEOMETRY="1920x1080"
VNC_PASSWORD="vnc123"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if already running
check_running() {
    if vncserver -list 2>/dev/null | grep -q "^1"; then
        log_warn "VNC server already running on display $VNC_DISPLAY"
        return 0
    fi
    return 1
}

# Install dependencies if needed
install_deps() {
    log_info "Checking dependencies..."

    local deps=(
        "tigervnc-standalone-server"
        "openbox"
        "novnc"
        "gir1.2-atspi-2.0"
        "libatspi2.0-0"
        "at-spi2-core"
        "python3-gi"
        "xdotool"
        "scrot"
    )

    local missing=()
    for dep in "${deps[@]}"; do
        if ! dpkg -l "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${missing[*]}"
        apt update && apt install -y "${missing[@]}"
    fi
}

# Setup VNC password
setup_vnc_password() {
    mkdir -p ~/.vnc
    if [ ! -f ~/.vnc/passwd ]; then
        log_info "Setting VNC password..."
        printf "$VNC_PASSWORD\n$VNC_PASSWORD\nn\n" | vncpasswd
    fi
}

# Create xstartup for VNC
setup_xstartup() {
    cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
# Start dbus for accessibility
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Enable accessibility
export GTK_MODULES=gail:atk-bridge
export NO_AT_BRIDGE=0
export GNOME_ACCESSIBILITY=1

# Start the accessibility registry daemon
/usr/libexec/at-spi2-registryd &

# Start window manager
exec openbox-session
EOF
    chmod +x ~/.vnc/xstartup
}

# Start VNC server
start_vnc() {
    log_info "Starting VNC server on display $VNC_DISPLAY..."

    # Kill any existing session
    vncserver -kill $VNC_DISPLAY 2>/dev/null || true
    sleep 1

    # Start fresh
    vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth 24 -localhost no
    sleep 2

    if vncserver -list 2>/dev/null | grep -q "^1"; then
        log_info "VNC server started successfully"
    else
        log_error "Failed to start VNC server"
        exit 1
    fi
}

# Start noVNC for browser access
start_novnc() {
    log_info "Starting noVNC on port $NOVNC_PORT..."

    # Kill any existing
    pkill -f "websockify.*$NOVNC_PORT" 2>/dev/null || true
    sleep 1

    # Start websockify
    websockify --web=/usr/share/novnc $NOVNC_PORT localhost:$VNC_PORT &
    sleep 2

    log_info "noVNC started"
}

# Start Chrome with accessibility
start_chrome() {
    local url="${1:-about:blank}"

    log_info "Starting Chrome with accessibility enabled..."

    # Set environment for this shell
    export DISPLAY=$VNC_DISPLAY
    export GTK_MODULES=gail:atk-bridge
    export NO_AT_BRIDGE=0
    export GNOME_ACCESSIBILITY=1

    # Kill any existing Chrome
    pkill -9 chrome 2>/dev/null || true
    sleep 2

    # Chrome flags for accessibility and stability
    google-chrome \
        --no-sandbox \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-dev-shm-usage \
        --start-maximized \
        --force-renderer-accessibility \
        --disable-extensions \
        --disable-background-networking \
        --disable-sync \
        --disable-translate \
        --no-first-run \
        --no-default-browser-check \
        "$url" &

    sleep 5

    if pgrep -f "chrome.*no-sandbox" > /dev/null; then
        log_info "Chrome started successfully"
    else
        log_error "Failed to start Chrome"
        exit 1
    fi
}

# Get IP address
get_ip() {
    hostname -I | awk '{print $1}'
}

# Main
main() {
    log_info "=== Chrome Automation Setup ==="

    # Parse arguments
    local url="${1:-about:blank}"

    # Setup
    install_deps
    setup_vnc_password
    setup_xstartup

    # Start services
    if ! check_running; then
        start_vnc
    fi
    start_novnc
    start_chrome "$url"

    # Get connection info
    local ip=$(get_ip)

    echo ""
    log_info "=== Setup Complete ==="
    echo ""
    echo "VNC Connection:"
    echo "  Address:  $ip:$VNC_PORT"
    echo "  Password: $VNC_PASSWORD"
    echo ""
    echo "Browser Access:"
    echo "  URL: http://$ip:$NOVNC_PORT/vnc.html"
    echo ""
    echo "Control Chrome:"
    echo "  chrome-a11y click 'Button Name'"
    echo "  chrome-a11y list"
    echo "  chrome-a11y type 'text to type'"
    echo ""
}

main "$@"
