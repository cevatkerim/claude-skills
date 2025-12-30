# Chrome Automation System - Summary

## Location
All files are in: `/root/chrome-automation/`

## Key Discovery
**xdotool mouse clicks don't work reliably with Chrome** due to Chrome's GPU compositor bypassing X11 input. The solution is **AT-SPI** (Assistive Technology Service Provider Interface) which uses Chrome's accessibility tree.

## Files Created

| File | Purpose |
|------|---------|
| `setup.sh` | One-time setup - installs all dependencies |
| `start-chrome-automation.sh` | Starts VNC + Chrome with accessibility |
| `stop-chrome-automation.sh` | Stops all services |
| `chrome-a11y` | Main control tool (click, type, navigate) |
| `chrome-monitor.py` | Background daemon for auto-dismiss |

## Quick Reference

### Start Everything
```bash
start-chrome-automation https://google.com
```

### Control Chrome
```bash
# List all clickable elements
chrome-a11y list

# Click by name
chrome-a11y click "Sign in"
chrome-a11y click "Google Search"

# Navigate
chrome-a11y navigate "https://example.com"

# Type text (uses xdotool - still works for keyboard)
chrome-a11y type "search query"

# Send keys
chrome-a11y key "ctrl+l"    # Focus address bar
chrome-a11y key "ctrl+t"    # New tab
chrome-a11y key "Return"    # Enter

# Switch tabs
chrome-a11y tab 1
chrome-a11y tab 2
```

### Background Monitor
```bash
chrome-monitor start    # Auto-dismiss popups
chrome-monitor status
chrome-monitor stop
```

### Stop Everything
```bash
stop-chrome-automation
```

## Chrome Launch Flags (Critical)

```bash
google-chrome \
    --no-sandbox \                    # Required for root
    --disable-gpu \                   # Stability in VNC
    --force-renderer-accessibility \  # CRITICAL: Enables AT-SPI
    --disable-extensions \            # Prevents crashes
    --start-maximized \
    --no-first-run \
    --disable-background-networking \
    &                                 # MUST run in background
```

## Environment Variables

```bash
export DISPLAY=:1
export GTK_MODULES=gail:atk-bridge
export NO_AT_BRIDGE=0
export GNOME_ACCESSIBILITY=1
```

## Connection Info

| Service | Address | Notes |
|---------|---------|-------|
| VNC | `<ip>:5901` | Password: vnc123 |
| noVNC | `http://<ip>:6080/vnc.html` | Browser access |

## How AT-SPI Works

1. Chrome exposes UI elements via accessibility tree
2. AT-SPI queries this tree to find elements by name/role
3. Elements have an "action interface" with click/activate
4. We invoke the action programmatically

```python
# Simplified example
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi

Atspi.init()
desktop = Atspi.get_desktop(0)
# Find Chrome app, traverse tree, find element, click
element.get_action_iface().do_action(0)
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Chrome not found in accessibility tree" | Ensure `--force-renderer-accessibility` flag |
| Clicks not working | Use `chrome-a11y` instead of `xdotool click` |
| Chrome crashes | Add `--disable-extensions` |
| Black screen | VNC not running - `vncserver :1` |
| Can't connect VNC | Check firewall, use noVNC as fallback |

## Dependencies

```bash
apt install -y \
    tigervnc-standalone-server \
    openbox \
    novnc \
    gir1.2-atspi-2.0 \
    at-spi2-core \
    python3-gi \
    xdotool \
    scrot
```
