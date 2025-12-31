#!/bin/bash
# Meeting Recorder Setup Script
# One-time installation of all dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEACHES_DIR="/opt/speaches"
CONFIG_FILE="$HOME/.meeting-recorder.json"
MEETINGS_DIR="/tmp/meetings"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Meeting Recorder Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Warning: Not running as root. Some installations may fail.${NC}"
fi

# Step 1: Install system packages
echo -e "${BLUE}[1/6] Installing system packages...${NC}"

# Check what's already installed
PACKAGES_TO_INSTALL=""

if ! command -v pulseaudio &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL pulseaudio"
fi

if ! command -v pactl &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL pulseaudio-utils"
fi

if ! command -v ffmpeg &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL ffmpeg"
fi

if ! command -v jq &> /dev/null; then
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL jq"
fi

if [ -n "$PACKAGES_TO_INSTALL" ]; then
    echo "Installing: $PACKAGES_TO_INSTALL"
    apt-get update -qq
    apt-get install -y $PACKAGES_TO_INSTALL
    echo -e "${GREEN}System packages installed${NC}"
else
    echo -e "${GREEN}System packages already installed${NC}"
fi

# Step 2: Install Python packages
echo ""
echo -e "${BLUE}[2/6] Installing Python packages...${NC}"

# Try pip with --break-system-packages for modern Python
pip3 install --quiet --upgrade --break-system-packages \
    websockets \
    aiofiles \
    requests \
    2>/dev/null || \
pip3 install --quiet --upgrade \
    websockets \
    aiofiles \
    requests \
    2>/dev/null || \
pip install --quiet --upgrade --break-system-packages \
    websockets \
    aiofiles \
    requests \
    2>/dev/null || \
echo -e "${YELLOW}Warning: pip install failed. Try: pip3 install --break-system-packages websockets aiofiles requests${NC}"

echo -e "${GREEN}Python packages installed${NC}"

# Step 3: Setup Speaches Docker
echo ""
echo -e "${BLUE}[3/6] Setting up Speaches (Speech-to-Text server)...${NC}"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker not installed. Please install Docker first.${NC}"
    exit 1
fi

# Create Speaches directory
mkdir -p "$SPEACHES_DIR"

# Create compose file
cat > "$SPEACHES_DIR/compose.cpu.yaml" << 'EOF'
services:
  speaches:
    image: ghcr.io/speaches-ai/speaches:latest-cpu
    container_name: speaches
    ports:
      - "8000:8000"
    environment:
      - SPEACHES_DEVICE=cpu
      - SPEACHES_COMPUTE_TYPE=int8
    volumes:
      - speaches-cache:/root/.cache
    restart: unless-stopped

volumes:
  speaches-cache:
EOF

# Check if Speaches is already running
if docker ps --format '{{.Names}}' | grep -q "^speaches$"; then
    echo -e "${GREEN}Speaches already running${NC}"
else
    echo "Starting Speaches container (this may take a moment on first run)..."
    cd "$SPEACHES_DIR"
    docker compose -f compose.cpu.yaml up -d

    # Wait for health
    echo "Waiting for Speaches to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8000/health > /dev/null 2>&1; then
            echo -e "${GREEN}Speaches is ready${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}Warning: Speaches not responding yet. It may still be starting.${NC}"
            echo "Check status with: curl http://localhost:8000/health"
        fi
        sleep 2
    done
fi

# Step 4: Create configuration file
echo ""
echo -e "${BLUE}[4/6] Creating configuration...${NC}"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
{
    "participant_name": "Claude Assistant",
    "meetings_dir": "/tmp/meetings",
    "mention_keywords": ["claude", "assistant", "ai", "hey claude"],
    "speaches_url": "ws://localhost:8000/v1/realtime",
    "transcription_model": "Systran/faster-distil-whisper-small.en",
    "audio_sample_rate": 24000,
    "chunk_duration_ms": 500
}
EOF
    echo -e "${GREEN}Created $CONFIG_FILE${NC}"
else
    echo -e "${GREEN}Config already exists: $CONFIG_FILE${NC}"
fi

# Create meetings directory
mkdir -p "$MEETINGS_DIR"
echo "Meetings will be stored at: $MEETINGS_DIR"

# Step 5: Create symlinks
echo ""
echo -e "${BLUE}[5/6] Creating symlinks...${NC}"

# Link to launch.sh
LAUNCH_SCRIPT="$SCRIPT_DIR/../launch.sh"
if [ -f "$LAUNCH_SCRIPT" ]; then
    ln -sf "$(realpath "$LAUNCH_SCRIPT")" /usr/local/bin/meeting-recorder
    echo -e "${GREEN}Created /usr/local/bin/meeting-recorder${NC}"
fi

# Step 6: Make scripts executable
echo ""
echo -e "${BLUE}[6/6] Making scripts executable...${NC}"

chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/*.py 2>/dev/null || true
chmod +x "$SCRIPT_DIR/../launch.sh" 2>/dev/null || true

echo -e "${GREEN}Scripts are executable${NC}"

# Final summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Components installed:"
echo "  - PulseAudio (audio routing)"
echo "  - Speaches (speech-to-text on port 8000)"
echo "  - Python packages (websockets, aiofiles, requests)"
echo ""
echo "Quick start:"
echo "  meeting-recorder join \"https://meet.google.com/xxx-yyyy-zzz\""
echo ""
echo "Configuration: $CONFIG_FILE"
echo "Transcripts: $MEETINGS_DIR"
echo ""

# Check chrome-automation is available
if ! command -v chrome-a11y &> /dev/null; then
    echo -e "${YELLOW}Note: chrome-a11y not found in PATH.${NC}"
    echo "Make sure chrome-automation skill is installed and setup."
fi
