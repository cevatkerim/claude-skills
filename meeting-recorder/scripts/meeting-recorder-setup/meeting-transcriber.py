#!/usr/bin/env python3
"""
Meeting Transcriber - WebSocket client for Speaches real-time transcription

Reads raw PCM audio from stdin (piped from parecord)
Streams to Speaches WebSocket API
Writes transcriptions to meeting directory

Usage:
    audio-capture.sh | meeting-transcriber.py <meeting_id> <meeting_url>
"""

import asyncio
import base64
import json
import sys
import os
import re
import signal
from datetime import datetime, timezone
from pathlib import Path

try:
    import websockets
    from websockets.exceptions import ConnectionClosed
except ImportError:
    print("Error: websockets package not installed. Run: pip install websockets", file=sys.stderr)
    sys.exit(1)

# Configuration (can be overridden via environment)
SAMPLE_RATE = int(os.getenv("SAMPLE_RATE", "24000"))
CHUNK_SIZE = SAMPLE_RATE  # 1 second of 16-bit mono audio = sample_rate * 2 bytes
SPEACHES_URL = os.getenv("SPEACHES_URL", "ws://localhost:8000/v1/realtime")
TRANSCRIPTION_MODEL = os.getenv("TRANSCRIPTION_MODEL", "Systran/faster-distil-whisper-small.en")
MEETINGS_DIR = os.getenv("MEETINGS_DIR", "/tmp/meetings")

# Mention detection keywords (loaded from config)
MENTION_KEYWORDS = ["claude", "assistant", "ai"]


class MeetingTranscriber:
    def __init__(self, meeting_id: str, meeting_url: str):
        self.meeting_id = meeting_id
        self.meeting_url = meeting_url
        self.meeting_dir = Path(MEETINGS_DIR) / meeting_id
        self.transcript_path = self.meeting_dir / "transcript.txt"
        self.metadata_path = self.meeting_dir / "metadata.json"
        self.mentions_path = self.meeting_dir / "mentions.txt"
        self.ws = None
        self.running = True
        self.reconnect_delay = 1
        self.max_reconnect_delay = 30

        # Load config if available
        self._load_config()

    def _load_config(self):
        """Load configuration from ~/.meeting-recorder.json"""
        config_path = Path.home() / ".meeting-recorder.json"
        if config_path.exists():
            try:
                with open(config_path) as f:
                    config = json.load(f)
                global MENTION_KEYWORDS
                MENTION_KEYWORDS = config.get("mention_keywords", MENTION_KEYWORDS)
            except Exception:
                pass

    def setup_meeting_directory(self):
        """Create meeting directory and initialize files"""
        self.meeting_dir.mkdir(parents=True, exist_ok=True)

        # Initialize transcript file
        self.transcript_path.write_text("")

        # Initialize mentions file
        self.mentions_path.write_text("")

        # Create metadata
        metadata = {
            "meeting_id": self.meeting_id,
            "url": self.meeting_url,
            "started_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "ended_at": None,
            "participant_name": self._get_participant_name(),
            "status": "active"
        }
        with open(self.metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)

        # Update 'current' symlink
        current_link = Path(MEETINGS_DIR) / "current"
        if current_link.is_symlink():
            current_link.unlink()
        current_link.symlink_to(self.meeting_dir)

        print(f"Meeting directory: {self.meeting_dir}", file=sys.stderr)

    def _get_participant_name(self) -> str:
        """Get participant name from config"""
        config_path = Path.home() / ".meeting-recorder.json"
        if config_path.exists():
            try:
                with open(config_path) as f:
                    return json.load(f).get("participant_name", "Claude Assistant")
            except Exception:
                pass
        return "Claude Assistant"

    async def connect(self):
        """Connect to Speaches WebSocket"""
        url = f"{SPEACHES_URL}?model={TRANSCRIPTION_MODEL}&intent=transcription"
        print(f"Connecting to Speaches: {url}", file=sys.stderr)

        self.ws = await websockets.connect(url)

        # Configure session for transcription-only mode
        session_config = {
            "type": "session.update",
            "session": {
                "modalities": ["text"],  # Text only, no audio response
                "input_audio_transcription": {
                    "model": TRANSCRIPTION_MODEL,
                    "language": "en"
                },
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 500,
                    "create_response": False  # No AI response, just transcription
                }
            }
        }
        await self.ws.send(json.dumps(session_config))
        print("Session configured for transcription", file=sys.stderr)

        # Reset reconnect delay on successful connection
        self.reconnect_delay = 1

    def _ws_is_open(self) -> bool:
        """Check if websocket connection is open (compatible with various websockets versions)"""
        if not self.ws:
            return False
        try:
            # websockets 10+ uses state
            if hasattr(self.ws, 'state'):
                import websockets
                return self.ws.state == websockets.protocol.State.OPEN
            # Older versions use open
            if hasattr(self.ws, 'open'):
                return self.ws.open
            return True  # Assume open if we can't check
        except Exception:
            return False

    async def send_audio(self):
        """Read audio from stdin and send to WebSocket"""
        loop = asyncio.get_event_loop()
        bytes_per_chunk = CHUNK_SIZE * 2  # 16-bit audio = 2 bytes per sample

        while self.running:
            try:
                # Read chunk from stdin (piped from parecord)
                chunk = await loop.run_in_executor(
                    None,
                    sys.stdin.buffer.read,
                    bytes_per_chunk
                )

                if not chunk:
                    print("Audio stream ended", file=sys.stderr)
                    break

                if self.ws:
                    # Encode and send
                    audio_event = {
                        "type": "input_audio_buffer.append",
                        "audio": base64.b64encode(chunk).decode()
                    }
                    try:
                        await self.ws.send(json.dumps(audio_event))
                    except ConnectionClosed:
                        print("WebSocket closed while sending", file=sys.stderr)
                        await self._reconnect()

            except Exception as e:
                print(f"Error sending audio: {e}", file=sys.stderr)
                break

    async def receive_transcriptions(self):
        """Receive transcription events and write to file"""
        while self.running:
            try:
                if not self.ws:
                    await asyncio.sleep(0.1)
                    continue

                message = await self.ws.recv()
                event = json.loads(message)

                event_type = event.get("type", "")

                # Handle transcription completion
                if event_type == "conversation.item.input_audio_transcription.completed":
                    transcript = event.get("transcript", "").strip()
                    if transcript:
                        self._write_transcript(transcript)

                # Handle VAD events (optional logging)
                elif event_type == "input_audio_buffer.speech_started":
                    pass  # Could log "Speech detected"
                elif event_type == "input_audio_buffer.speech_stopped":
                    pass  # Could log "Speech ended"

                # Handle errors
                elif event_type == "error":
                    error = event.get("error", {})
                    print(f"Speaches error: {error}", file=sys.stderr)

            except ConnectionClosed:
                print("WebSocket connection closed", file=sys.stderr)
                await self._reconnect()
            except Exception as e:
                print(f"Error receiving: {e}", file=sys.stderr)
                await asyncio.sleep(1)

    def _write_transcript(self, transcript: str):
        """Write transcript line and check for mentions"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {transcript}\n"

        # Append to transcript file
        with open(self.transcript_path, "a") as f:
            f.write(line)

        # Also print to stderr for debugging
        print(f"[{timestamp}] {transcript}", file=sys.stderr)

        # Check for mentions/questions
        self._check_mentions(timestamp, transcript)

    def _check_mentions(self, timestamp: str, transcript: str):
        """Check if transcript contains mention keywords + question"""
        lower_transcript = transcript.lower()

        # Check for keyword mentions
        for keyword in MENTION_KEYWORDS:
            if keyword.lower() in lower_transcript:
                # Check if it's a question (contains ?)
                is_question = "?" in transcript

                # Also detect question phrases
                question_phrases = [
                    "what do you think",
                    "can you",
                    "could you",
                    "would you",
                    "do you know",
                    "what about",
                    "hey claude",
                    "hey assistant"
                ]
                is_question = is_question or any(p in lower_transcript for p in question_phrases)

                if is_question:
                    mention_line = f"[{timestamp}] QUESTION: {transcript}\n"
                else:
                    mention_line = f"[{timestamp}] MENTION: {transcript}\n"

                with open(self.mentions_path, "a") as f:
                    f.write(mention_line)

                print(f">>> MENTION DETECTED: {transcript}", file=sys.stderr)
                break

    async def _reconnect(self):
        """Attempt to reconnect with exponential backoff"""
        if not self.running:
            return

        print(f"Reconnecting in {self.reconnect_delay}s...", file=sys.stderr)
        await asyncio.sleep(self.reconnect_delay)

        self.reconnect_delay = min(self.reconnect_delay * 2, self.max_reconnect_delay)

        try:
            await self.connect()
        except Exception as e:
            print(f"Reconnect failed: {e}", file=sys.stderr)

    def update_metadata_ended(self):
        """Update metadata when meeting ends"""
        if self.metadata_path.exists():
            try:
                with open(self.metadata_path) as f:
                    metadata = json.load(f)
                metadata["ended_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                metadata["status"] = "ended"
                with open(self.metadata_path, "w") as f:
                    json.dump(metadata, f, indent=2)
            except Exception as e:
                print(f"Error updating metadata: {e}", file=sys.stderr)

    async def run(self):
        """Main entry point"""
        # Setup signal handlers
        def signal_handler(sig, frame):
            print("\nShutting down...", file=sys.stderr)
            self.running = False

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        # Setup meeting directory
        self.setup_meeting_directory()

        try:
            await self.connect()

            # Run send and receive concurrently
            await asyncio.gather(
                self.send_audio(),
                self.receive_transcriptions(),
                return_exceptions=True
            )
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
        finally:
            self.running = False
            self.update_metadata_ended()

            if self.ws:
                await self.ws.close()

            # Remove 'current' symlink
            current_link = Path(MEETINGS_DIR) / "current"
            if current_link.is_symlink():
                try:
                    current_link.unlink()
                except Exception:
                    pass

            print("Transcriber stopped", file=sys.stderr)


def extract_meeting_id(url: str) -> str:
    """Extract meeting ID from Google Meet URL"""
    # Pattern: meet.google.com/xxx-yyyy-zzz
    match = re.search(r'meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3})', url.lower())
    if match:
        return match.group(1)

    # Fallback: use last path segment
    parts = url.rstrip('/').split('/')
    if parts:
        return parts[-1]

    return "unknown"


def main():
    if len(sys.argv) < 2:
        print("Usage: meeting-transcriber.py <meeting_id> [meeting_url]", file=sys.stderr)
        print("  Reads PCM audio from stdin and streams to Speaches", file=sys.stderr)
        sys.exit(1)

    meeting_id = sys.argv[1]
    meeting_url = sys.argv[2] if len(sys.argv) > 2 else f"https://meet.google.com/{meeting_id}"

    transcriber = MeetingTranscriber(meeting_id, meeting_url)
    asyncio.run(transcriber.run())


if __name__ == "__main__":
    main()
