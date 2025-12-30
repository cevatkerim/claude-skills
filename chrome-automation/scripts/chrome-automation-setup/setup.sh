#!/bin/bash
#
# Chrome Automation Setup Script
# Installs all dependencies and configures the system
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Chrome Automation Setup ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

echo "[1/5] Installing system packages..."
apt update
apt install -y \
    google-chrome-stable \
    tigervnc-standalone-server \
    tigervnc-common \
    openbox \
    novnc \
    gir1.2-atspi-2.0 \
    libatspi2.0-0 \
    at-spi2-core \
    python3-gi \
    python3-gi-cairo \
    xdotool \
    scrot \
    dbus-x11

echo ""
echo "[2/5] Setting up VNC..."
mkdir -p ~/.vnc

# Set VNC password
echo "Setting VNC password to 'vnc123'..."
printf "vnc123\nvnc123\nn\n" | vncpasswd

# Create xstartup
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi
export GTK_MODULES=gail:atk-bridge
export NO_AT_BRIDGE=0
export GNOME_ACCESSIBILITY=1
/usr/libexec/at-spi2-registryd &
exec openbox-session
EOF
chmod +x ~/.vnc/xstartup

echo ""
echo "[3/5] Making scripts executable..."
chmod +x "$SCRIPT_DIR/start-chrome-automation.sh"
chmod +x "$SCRIPT_DIR/stop-chrome-automation.sh"
chmod +x "$SCRIPT_DIR/chrome-a11y"
chmod +x "$SCRIPT_DIR/chrome-monitor.py"

echo ""
echo "[4/5] Creating symlinks in /usr/local/bin..."
ln -sf "$SCRIPT_DIR/start-chrome-automation.sh" /usr/local/bin/start-chrome-automation
ln -sf "$SCRIPT_DIR/stop-chrome-automation.sh" /usr/local/bin/stop-chrome-automation
ln -sf "$SCRIPT_DIR/chrome-a11y" /usr/local/bin/chrome-a11y
ln -sf "$SCRIPT_DIR/chrome-monitor.py" /usr/local/bin/chrome-monitor

echo ""
echo "[5/5] Creating default configuration..."
cat > ~/.chrome-monitor.json << 'EOF'
{
    "poll_interval": 2.0,
    "auto_dismiss_enabled": true,
    "auto_dismiss": [
        {"name": "Not now", "role": "push button"},
        {"name": "No thanks", "role": "push button"},
        {"name": "Dismiss", "role": "push button"},
        {"name": "Got it", "role": "push button"},
        {"name": "I agree", "role": "push button"},
        {"name": "Accept all", "role": "push button"},
        {"name": "Close", "role": "push button"}
    ],
    "log_elements": false
}
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick Start:"
echo "  start-chrome-automation https://google.com"
echo ""
echo "Control Chrome:"
echo "  chrome-a11y click 'Button Name'"
echo "  chrome-a11y list"
echo "  chrome-a11y type 'text'"
echo "  chrome-a11y navigate 'https://example.com'"
echo ""
echo "Background Monitor:"
echo "  chrome-monitor start"
echo "  chrome-monitor status"
echo "  chrome-monitor stop"
echo ""
echo "Stop Everything:"
echo "  stop-chrome-automation"
echo ""
