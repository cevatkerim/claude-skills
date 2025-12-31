# Meeting Recorder - Technical Reference

## Architecture

```
User provides meeting URL (e.g., meet.google.com/abc-defg-hij)
         ↓
Extract meeting ID → abc-defg-hij
         ↓
chrome-a11y navigates & joins call
         ↓
Chrome audio → PulseAudio virtual sink → parecord
         ↓
meeting-transcriber-batch.py → HTTP POST → Speaches (Docker/CPU)
         ↓
Transcriptions → /tmp/meetings/abc-defg-hij/transcript.txt
                 /tmp/meetings/abc-defg-hij/metadata.json
         ↓
Claude reads, summarizes, responds via chat
```

## Components

### 1. Speaches (Speech-to-Text Server)

Self-hosted, OpenAI-compatible STT/TTS server using faster-whisper.

- **Port**: 8000
- **Mode**: CPU (2-5 second latency per utterance)
- **Model**: `Systran/faster-distil-whisper-small.en`
- **API**: OpenAI-compatible HTTP API (`/v1/audio/transcriptions`)
- **Docker Image**: `ghcr.io/speaches-ai/speaches:latest-cpu`

Health check:
```bash
curl http://localhost:8000/health
```

#### Installing the Whisper Model

Models are not included in the Docker image and must be downloaded before first use:

```bash
# Download the model (required before transcription works)
curl -X POST "http://localhost:8000/v1/models/Systran%2Ffaster-distil-whisper-small.en"

# Verify model is installed
curl http://localhost:8000/v1/models | jq '.'
```

**Note**: The model ID must be URL-encoded (slash becomes `%2F`).

Available models in registry:
```bash
# List all available STT models
curl http://localhost:8000/v1/registry | jq '.data[] | select(.task == "automatic-speech-recognition") | .id'
```

### 2. PulseAudio Virtual Sink

Captures Chrome's audio output without affecting speakers.

```bash
# Create sink
pactl load-module module-null-sink sink_name=meeting_capture \
    sink_properties=device.description="Meeting_Audio_Capture"

# List sinks
pactl list sinks short

# Remove sink
pactl unload-module module-null-sink
```

### 3. Audio Capture Pipeline

```bash
# Capture audio as raw PCM
parecord -d meeting_capture.monitor --raw --rate=24000 --channels=1 --format=s16le
```

Parameters:
- Sample rate: 24000 Hz (Speaches requirement)
- Channels: 1 (mono)
- Format: s16le (16-bit signed little-endian PCM)

### 4. Chrome Integration

#### Starting Chrome with Audio Support

Chrome must be started with specific flags and environment variables for audio capture:

```bash
# Required environment variables
export DISPLAY=:1
export PULSE_SERVER=unix:/run/pulse/native

# Start Chrome with audio and media flags
nohup /opt/google/chrome/chrome \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --use-fake-ui-for-media-stream \
    --use-fake-device-for-media-stream \
    --enable-features=AccessibilityFocusRing \
    --autoplay-policy=no-user-gesture-required \
    "https://meet.google.com/xxx-yyyy-zzz" \
    > /tmp/chrome.log 2>&1 &
```

**Flag explanations:**
| Flag | Purpose |
|------|---------|
| `--no-sandbox` | Required for running as root |
| `--disable-gpu` | Prevents GPU errors in headless environments |
| `--use-fake-ui-for-media-stream` | Auto-accepts camera/mic permission prompts |
| `--use-fake-device-for-media-stream` | Uses fake devices (shows "Fake Default" in Meet) |
| `--enable-features=AccessibilityFocusRing` | Enables AT-SPI2 accessibility |
| `--autoplay-policy=no-user-gesture-required` | Allows audio playback without user interaction |

#### Routing Chrome Audio to Capture Sink

After Chrome starts playing audio, route it to the capture sink:

```bash
# Find Chrome's audio sink input
SINK_INPUT=$(pactl list sink-inputs short | grep -i "chrome" | awk '{print $1}' | head -1)

# Move to meeting_capture sink
pactl move-sink-input "$SINK_INPUT" meeting_capture

# Verify routing
pactl list sink-inputs short
```

#### Browser Control

Uses Claude-in-Chrome MCP or `chrome-a11y` (AT-SPI2) for browser control:

```bash
# AT-SPI2 method
chrome-a11y navigate "https://meet.google.com/xxx-yyyy-zzz"
chrome-a11y click "Join now"
chrome-a11y click "Chat with everyone"
chrome-a11y type "Hello!"
chrome-a11y key "Return"
```

## File Structure

```
/root/claude-skills/meeting-recorder/
├── SKILL.md                           # Skill metadata
├── REFERENCE.md                       # This file
└── scripts/
    ├── launch.sh                      # Main CLI entry point
    └── meeting-recorder-setup/
        ├── setup.sh                   # One-time installation
        ├── start-meeting.sh           # Join and start transcription
        ├── stop-meeting.sh            # Leave and cleanup
        ├── send-chat.sh               # Send message to chat
        ├── meeting-transcriber-batch.py # HTTP-based transcriber (primary)
        ├── meeting-transcriber.py     # WebSocket audio bridge (legacy)
        ├── audio-capture.sh           # PulseAudio capture helper
        └── compose.cpu.yaml           # Speaches Docker config
```

## Meeting Storage

```
/tmp/meetings/
├── abc-defg-hij/                    # Meeting ID from URL
│   ├── transcript.txt               # Full transcript
│   ├── metadata.json                # Meeting info
│   └── mentions.txt                 # Detected mentions
├── xyz-uvwx-rst/                    # Another meeting
│   └── ...
└── current -> abc-defg-hij/         # Symlink to active
```

### metadata.json Format

```json
{
    "meeting_id": "abc-defg-hij",
    "url": "https://meet.google.com/abc-defg-hij",
    "started_at": "2025-12-30T14:30:00Z",
    "ended_at": null,
    "participant_name": "Claude Assistant",
    "status": "active"
}
```

### transcript.txt Format

```
[14:30:05] Hello everyone, let's get started.
[14:30:12] Thanks for joining. First agenda item...
[14:31:45] Claude, what do you think about this?
```

### mentions.txt Format

```
[14:31:45] QUESTION: Claude, what do you think about this?
```

## CLI Commands

### `meeting-recorder join <url> [name]`

Join a Google Meet and start transcription.

```bash
meeting-recorder join "https://meet.google.com/abc-defg-hij"
meeting-recorder join "https://meet.google.com/abc-defg-hij" "My Bot Name"
```

### `meeting-recorder leave`

Leave the current meeting and stop transcription.

### `meeting-recorder chat <message>`

Send a message to the meeting chat.

```bash
meeting-recorder chat "I can help with that question!"
```

### `meeting-recorder status`

Show current meeting status.

Output:
```
Meeting in progress: abc-defg-hij
Transcript lines: 142
Duration: 00:23:45
```

### `meeting-recorder transcript [meeting_id]`

Display transcript (current meeting if no ID given).

## Configuration

### ~/.meeting-recorder.json

```json
{
    "participant_name": "Claude Assistant",
    "meetings_dir": "/tmp/meetings",
    "mention_keywords": ["claude", "assistant", "ai"],
    "speaches_url": "ws://localhost:8000/v1/realtime",
    "transcription_model": "Systran/faster-distil-whisper-small.en",
    "audio_sample_rate": 24000,
    "chunk_duration_ms": 500
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `participant_name` | Name shown in meeting | "Claude Assistant" |
| `meetings_dir` | Where to store transcripts | "/tmp/meetings" |
| `mention_keywords` | Words to detect for alerts | ["claude", "assistant", "ai"] |
| `speaches_url` | Speaches WebSocket endpoint | "ws://localhost:8000/v1/realtime" |
| `transcription_model` | Whisper model to use | "Systran/faster-distil-whisper-small.en" |
| `audio_sample_rate` | Audio sample rate (Hz) | 24000 |
| `chunk_duration_ms` | Audio chunk size (ms) | 500 |

## Speaches Transcription API

### Batch HTTP API (Primary Method)

The batch transcriber sends audio chunks via HTTP POST for reliable transcription:

```bash
curl -X POST http://localhost:8000/v1/audio/transcriptions \
    -F "file=@audio.wav" \
    -F "model=Systran/faster-distil-whisper-small.en"
```

Response:
```json
{
    "text": "Hello everyone, let's get started."
}
```

### Batch Transcriber Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `CHUNK_DURATION` | 5 | Seconds of audio per batch |
| `SAMPLE_RATE` | 24000 | Audio sample rate (Hz) |
| `SPEACHES_URL` | `http://localhost:8000` | Speaches HTTP endpoint |

### WebSocket API (Legacy)

The WebSocket API (`/v1/realtime`) is available but may have compatibility issues with certain configurations. Use the batch HTTP API for reliability.

## Error Handling

| Error | Symptom | Solution |
|-------|---------|----------|
| Join timeout | No "Leave call" button after 60s | Check Chrome, retry |
| WebSocket disconnect | Transcription stops | Auto-reconnect |
| Chrome crash | Process not found | Restart chrome-automation |
| Speaches unavailable | Health check fails | `docker compose restart` |
| Audio capture fails | No PCM output | Check PulseAudio sink |

## Performance

| Metric | Value |
|--------|-------|
| Transcription latency | 2-5 seconds (CPU mode) |
| Memory usage | ~2GB total |
| Audio quality | 24kHz mono (sufficient for speech) |

## Troubleshooting

### Check Speaches is running

```bash
curl http://localhost:8000/health
docker ps | grep speaches
```

### Check PulseAudio

```bash
pactl list sinks short
pactl list sink-inputs  # Shows Chrome audio routing
```

### Check Chrome

```bash
pgrep -f "chrome.*no-sandbox"
chrome-a11y list | head -20
```

### View logs

```bash
# Transcriber output
tail -f /tmp/meetings/current/transcript.txt

# Docker logs
docker logs speaches 2>&1 | tail -50
```

### Manual testing

```bash
# Test audio capture
parecord -d meeting_capture.monitor --raw --rate=24000 --channels=1 | head -c 48000 > /tmp/test.raw

# Test Speaches connection
curl -X POST http://localhost:8000/v1/audio/transcriptions \
    -F "file=@/tmp/test.raw" \
    -F "model=Systran/faster-distil-whisper-small.en"
```

## Dependencies

### System Packages

- `pulseaudio` - Audio server
- `pulseaudio-utils` - pactl, parecord
- `ffmpeg` - Audio processing (optional)

### Python Packages

- `requests` - HTTP client (for batch transcriber)
- `websockets` - WebSocket client (for legacy transcriber)
- `aiofiles` - Async file I/O

### Docker

- Speaches container (ghcr.io/speaches-ai/speaches)
