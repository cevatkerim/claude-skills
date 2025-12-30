# Chrome Automation Reference

## Why AT-SPI2?

Standard mouse automation tools like `xdotool` do not work reliably with Chrome because Chrome uses its own GPU-accelerated compositor that bypasses X11 input events.

AT-SPI2 (Assistive Technology Service Provider Interface) solves this by using Chrome's accessibility tree. When Chrome runs with `--force-renderer-accessibility`, it exposes all UI elements (buttons, links, inputs) as accessible objects that can be clicked programmatically.

## Chrome Launch Flags

| Flag | Required | Purpose |
|------|----------|---------|
| `--no-sandbox` | Yes (as root) | Disables Chrome sandbox (required when running as root) |
| `--disable-gpu` | Recommended | Prevents GPU-related crashes in VNC/headless |
| `--force-renderer-accessibility` | **Yes** | Exposes accessibility tree for AT-SPI2 |
| `--start-maximized` | Recommended | Fills VNC window |
| `--no-first-run` | Recommended | Skips first-run dialogs |
| `--disable-extensions` | Optional | Improves stability but disables extensions |
| `--disable-background-networking` | Optional | Reduces background activity |

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `DISPLAY` | `:1` | X11 display (TigerVNC) |
| `GTK_MODULES` | `gail:atk-bridge` | Enables GTK accessibility bridge |
| `NO_AT_BRIDGE` | `0` | Ensures AT-SPI bridge is active |
| `GNOME_ACCESSIBILITY` | `1` | Enables GNOME accessibility features |

## chrome-a11y Commands

The `chrome-a11y` tool (located at `/usr/local/bin/chrome-a11y`) provides these commands:

### list [filter]
List clickable elements. Optionally filter by name.
```bash
chrome-a11y list
chrome-a11y list "Sign"
```

### click "name"
Click an element by its accessible name.
```bash
chrome-a11y click "Sign in"
chrome-a11y click "Submit"
```

### type "text"
Type text using xdotool (keyboard input still works).
```bash
chrome-a11y type "Hello world"
```

### key "combo"
Send keyboard shortcut.
```bash
chrome-a11y key "ctrl+l"      # Address bar
chrome-a11y key "ctrl+t"      # New tab
chrome-a11y key "ctrl+w"      # Close tab
chrome-a11y key "Return"      # Enter
chrome-a11y key "Escape"      # Escape
```

### navigate "url"
Navigate to a URL (focuses address bar, types URL, presses Enter).
```bash
chrome-a11y navigate "https://google.com"
```

### screenshot [file]
Take a screenshot.
```bash
chrome-a11y screenshot
chrome-a11y screenshot /tmp/screen.png
```

### tab N
Switch to tab number (1-9).
```bash
chrome-a11y tab 2
```

## Troubleshooting

### "Chrome not found in accessibility tree"
- Ensure Chrome was launched with `--force-renderer-accessibility`
- Wait 3-5 seconds after launch
- Verify environment variables are set

### Clicks not working
- Do NOT use xdotool for mouse clicks
- Use `chrome-a11y click` instead
- Ensure element name matches exactly (use `chrome-a11y list` to see names)

### Chrome crashes
- Add `--disable-extensions`
- Add `--disable-dev-shm-usage` if in container with limited /dev/shm
- Check system memory with `free -h`

### VNC shows black screen
- Verify TigerVNC is running: `vncserver -list`
- Start if needed: `vncserver :1 -geometry 1920x1080 -depth 24`

## VNC Setup

If VNC is not running:
```bash
# Install if needed
apt install -y tigervnc-standalone-server openbox

# Set password
vncpasswd

# Create xstartup
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
export GTK_MODULES=gail:atk-bridge
export GNOME_ACCESSIBILITY=1
exec openbox-session
EOF
chmod +x ~/.vnc/xstartup

# Start VNC
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no
```

## Full Setup from Scratch

```bash
# 1. Install dependencies
apt install -y \
    google-chrome-stable \
    tigervnc-standalone-server \
    openbox \
    gir1.2-atspi-2.0 \
    at-spi2-core \
    python3-gi \
    xdotool \
    scrot

# 2. Setup VNC (see above)

# 3. Start VNC
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no

# 4. Launch Chrome
export DISPLAY=:1
export GTK_MODULES=gail:atk-bridge
google-chrome --no-sandbox --disable-gpu --force-renderer-accessibility &

# 5. Wait and test
sleep 5
chrome-a11y list
```
