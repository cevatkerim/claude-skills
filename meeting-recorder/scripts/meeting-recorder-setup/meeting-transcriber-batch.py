#!/usr/bin/env python3
"""
Meeting Transcriber (Batch Mode) - HTTP-based transcription using Speaches

Reads raw PCM audio from stdin (piped from parecord)
Batches audio into chunks and sends to Speaches HTTP API
Writes transcriptions to meeting directory

Usage:
    parecord ... | meeting-transcriber-batch.py <meeting_id> <meeting_url>
"""

import io
import json
import struct
import sys
import os
import re
import signal
import time
import wave
import threading
from datetime import datetime, timezone
from pathlib import Path
from queue import Queue, Empty

try:
    import requests
except ImportError:
    print("Error: requests package not installed. Run: pip install requests", file=sys.stderr)
    sys.exit(1)

# Configuration (can be overridden via environment)
SAMPLE_RATE = int(os.getenv("SAMPLE_RATE", "24000"))
CHUNK_DURATION = float(os.getenv("CHUNK_DURATION", "5"))  # seconds per batch
SPEACHES_URL = os.getenv("SPEACHES_URL", "http://localhost:8000")
TRANSCRIPTION_MODEL = os.getenv("TRANSCRIPTION_MODEL", "Systran/faster-distil-whisper-small.en")
MEETINGS_DIR = os.getenv("MEETINGS_DIR", "/tmp/meetings")

# Mention detection keywords (loaded from config)
MENTION_KEYWORDS = ["claude", "assistant", "ai"]


class MeetingTranscriberBatch:
    def __init__(self, meeting_id: str, meeting_url: str):
        self.meeting_id = meeting_id
        self.meeting_url = meeting_url
        self.meeting_dir = Path(MEETINGS_DIR) / meeting_id
        self.transcript_path = self.meeting_dir / "transcript.txt"
        self.metadata_path = self.meeting_dir / "metadata.json"
        self.mentions_path = self.meeting_dir / "mentions.txt"
        self.running = True
        self.audio_queue = Queue()

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

        # Initialize transcript file (don't overwrite if exists)
        if not self.transcript_path.exists():
            self.transcript_path.write_text("")

        # Initialize mentions file
        if not self.mentions_path.exists():
            self.mentions_path.write_text("")

        # Create or update metadata
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

    def read_audio(self):
        """Read audio from stdin and queue it for processing"""
        bytes_per_chunk = int(SAMPLE_RATE * CHUNK_DURATION * 2)  # 16-bit = 2 bytes per sample

        print(f"Reading audio at {SAMPLE_RATE}Hz, {CHUNK_DURATION}s chunks ({bytes_per_chunk} bytes)", file=sys.stderr)

        while self.running:
            try:
                chunk = sys.stdin.buffer.read(bytes_per_chunk)
                if not chunk:
                    print("Audio stream ended", file=sys.stderr)
                    break
                if len(chunk) >= bytes_per_chunk // 2:  # At least half a chunk
                    self.audio_queue.put(chunk)
            except Exception as e:
                print(f"Error reading audio: {e}", file=sys.stderr)
                break

        self.running = False

    def process_audio(self):
        """Process queued audio chunks and transcribe them"""
        print(f"Transcription endpoint: {SPEACHES_URL}/v1/audio/transcriptions", file=sys.stderr)

        while self.running or not self.audio_queue.empty():
            try:
                chunk = self.audio_queue.get(timeout=1)
            except Empty:
                continue

            try:
                # Convert PCM to WAV in memory
                wav_buffer = io.BytesIO()
                with wave.open(wav_buffer, 'wb') as wav_file:
                    wav_file.setnchannels(1)
                    wav_file.setsampwidth(2)  # 16-bit
                    wav_file.setframerate(SAMPLE_RATE)
                    wav_file.writeframes(chunk)
                wav_buffer.seek(0)

                # Send to Speaches
                response = requests.post(
                    f"{SPEACHES_URL}/v1/audio/transcriptions",
                    files={"file": ("audio.wav", wav_buffer, "audio/wav")},
                    data={"model": TRANSCRIPTION_MODEL},
                    timeout=30
                )

                if response.status_code == 200:
                    result = response.json()
                    transcript = result.get("text", "").strip()
                    if transcript:
                        self._write_transcript(transcript)
                else:
                    print(f"Transcription error {response.status_code}: {response.text[:100]}", file=sys.stderr)

            except requests.RequestException as e:
                print(f"Request error: {e}", file=sys.stderr)
            except Exception as e:
                print(f"Processing error: {e}", file=sys.stderr)

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

    def run(self):
        """Main entry point"""
        # Setup signal handlers
        def signal_handler(sig, frame):
            print("\nShutting down...", file=sys.stderr)
            self.running = False

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        # Setup meeting directory
        self.setup_meeting_directory()

        # Start threads
        reader_thread = threading.Thread(target=self.read_audio, daemon=True)
        processor_thread = threading.Thread(target=self.process_audio, daemon=True)

        print("Starting transcription...", file=sys.stderr)
        reader_thread.start()
        processor_thread.start()

        try:
            while self.running:
                time.sleep(0.5)
        except KeyboardInterrupt:
            self.running = False

        # Wait for threads to finish
        reader_thread.join(timeout=2)
        processor_thread.join(timeout=5)

        self.update_metadata_ended()

        # Remove 'current' symlink
        current_link = Path(MEETINGS_DIR) / "current"
        if current_link.is_symlink():
            try:
                current_link.unlink()
            except Exception:
                pass

        print("Transcriber stopped", file=sys.stderr)


def main():
    if len(sys.argv) < 2:
        print("Usage: meeting-transcriber-batch.py <meeting_id> [meeting_url]", file=sys.stderr)
        print("  Reads PCM audio from stdin and transcribes via Speaches HTTP API", file=sys.stderr)
        sys.exit(1)

    meeting_id = sys.argv[1]
    meeting_url = sys.argv[2] if len(sys.argv) > 2 else f"https://meet.google.com/{meeting_id}"

    transcriber = MeetingTranscriberBatch(meeting_id, meeting_url)
    transcriber.run()


if __name__ == "__main__":
    main()
