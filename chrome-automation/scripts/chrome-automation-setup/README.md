# Chrome Automation with Accessibility (AT-SPI)

## Overview

This setup allows programmatic control of Google Chrome in a headless Linux environment using:
- **TigerVNC** for remote display
- **AT-SPI** (Assistive Technology Service Provider Interface) for clicking/interacting with UI elements
- **xdotool** for keyboard input and shortcuts

## Why AT-SPI?

Standard tools like `xdotool` clicks don't work reliably with Chrome because:
- Chrome uses its own compositor/rendering
- GPU acceleration bypasses normal X11 input
- Security features block synthetic mouse events

AT-SPI solves this by using the accessibility tree - the same interface used by screen readers.

## Quick Start

```bash
# Start everything
./start-chrome-automation.sh

# Control Chrome
chrome-a11y click "Join now"
chrome-a11y list
chrome-a11y type "Hello world"

# Stop everything
./stop-chrome-automation.sh
```

## Components

1. **start-chrome-automation.sh** - Starts VNC, Chrome with accessibility
2. **chrome-a11y** - Main control script (click, type, list elements)
3. **chrome-monitor.py** - Background daemon for monitoring/automation

## Requirements

```bash
apt install -y \
    tigervnc-standalone-server \
    openbox \
    novnc \
    gir1.2-atspi-2.0 \
    libatspi2.0-0 \
    at-spi2-core \
    python3-pyatspi \
    xdotool \
    scrot
```

## Connection Details

- **VNC**: `<ip>:5901` (password: vnc123)
- **Browser**: `http://<ip>:6080/vnc.html`
