#!/usr/bin/env python3
"""
Chrome Monitor Daemon

Background service that monitors Chrome and can:
- Auto-dismiss dialogs and popups
- Watch for specific elements and trigger actions
- Log accessibility events
- Provide a simple API for automation

Usage:
    ./chrome-monitor.py start           # Start daemon
    ./chrome-monitor.py stop            # Stop daemon
    ./chrome-monitor.py status          # Check status
    ./chrome-monitor.py watch "text"    # Watch for element
"""

import sys
import os
import time
import json
import signal
import threading
from pathlib import Path

# Set up environment before importing gi
os.environ.setdefault('DISPLAY', ':1')
os.environ['GTK_MODULES'] = 'gail:atk-bridge'
os.environ['NO_AT_BRIDGE'] = '0'
os.environ['GNOME_ACCESSIBILITY'] = '1'

import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi

# Configuration
PID_FILE = "/tmp/chrome-monitor.pid"
LOG_FILE = "/tmp/chrome-monitor.log"
CONFIG_FILE = os.path.expanduser("~/.chrome-monitor.json")

# Default auto-dismiss patterns
DEFAULT_AUTO_DISMISS = [
    {"name": "Not now", "role": "push button"},
    {"name": "No thanks", "role": "push button"},
    {"name": "Dismiss", "role": "push button"},
    {"name": "Close", "role": "push button", "context": "notification"},
    {"name": "Got it", "role": "push button"},
    {"name": "I agree", "role": "push button"},
    {"name": "Accept all", "role": "push button"},
    {"name": "Decline", "role": "push button", "context": "optional cookies"},
]


class ChromeMonitor:
    """Monitor Chrome accessibility tree and perform automated actions."""

    def __init__(self):
        Atspi.init()
        self.running = False
        self.config = self._load_config()
        self.log_file = open(LOG_FILE, 'a')
        self.watchers = []

    def _load_config(self):
        """Load configuration from file."""
        default_config = {
            "poll_interval": 2.0,
            "auto_dismiss": DEFAULT_AUTO_DISMISS,
            "auto_dismiss_enabled": True,
            "log_elements": False,
        }

        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE) as f:
                    user_config = json.load(f)
                    default_config.update(user_config)
            except Exception as e:
                self._log(f"Error loading config: {e}")

        return default_config

    def _log(self, message):
        """Log a message."""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{timestamp}] {message}"
        print(log_line)
        self.log_file.write(log_line + "\n")
        self.log_file.flush()

    def _find_chrome(self):
        """Find Chrome in accessibility tree."""
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app:
                name = (app.get_name() or "").lower()
                if "chrome" in name or "chromium" in name:
                    return app
        return None

    def _find_elements(self, obj, name_filter=None, role_filter=None,
                       depth=0, max_depth=25, results=None):
        """Find elements matching criteria."""
        if results is None:
            results = []

        if obj is None or depth > max_depth:
            return results

        try:
            role = obj.get_role_name()
            name = obj.get_name() or ""

            match = True
            if name_filter and name_filter.lower() not in name.lower():
                match = False
            if role_filter and role_filter.lower() != role.lower():
                match = False

            if match and name:
                results.append({
                    'obj': obj,
                    'name': name,
                    'role': role,
                })

            for i in range(obj.get_child_count()):
                self._find_elements(obj.get_child_at_index(i), name_filter,
                                   role_filter, depth + 1, max_depth, results)
        except:
            pass

        return results

    def _click_element(self, obj):
        """Click an element."""
        try:
            action = obj.get_action_iface()
            if action and action.get_n_actions() > 0:
                action.do_action(0)
                return True
        except:
            pass
        return False

    def _check_auto_dismiss(self, chrome):
        """Check for and dismiss popups/dialogs."""
        if not self.config.get("auto_dismiss_enabled"):
            return

        for pattern in self.config.get("auto_dismiss", []):
            elements = self._find_elements(
                chrome,
                name_filter=pattern.get("name"),
                role_filter=pattern.get("role")
            )

            for elem in elements:
                if self._click_element(elem['obj']):
                    self._log(f"Auto-dismissed: [{elem['role']}] {elem['name']}")
                    time.sleep(0.5)  # Brief pause after clicking
                    return True

        return False

    def _check_watchers(self, chrome):
        """Check for watched elements."""
        for watcher in self.watchers[:]:  # Copy list to allow modification
            elements = self._find_elements(
                chrome,
                name_filter=watcher.get("name"),
                role_filter=watcher.get("role")
            )

            if elements:
                elem = elements[0]
                self._log(f"Watcher triggered: [{elem['role']}] {elem['name']}")

                # Execute callback or action
                action = watcher.get("action", "log")
                if action == "click":
                    self._click_element(elem['obj'])
                    self._log(f"  -> Clicked")

                # Remove one-shot watchers
                if watcher.get("one_shot", False):
                    self.watchers.remove(watcher)

    def add_watcher(self, name, role=None, action="log", one_shot=False):
        """Add a watcher for an element."""
        self.watchers.append({
            "name": name,
            "role": role,
            "action": action,
            "one_shot": one_shot,
        })
        self._log(f"Added watcher for: {name}")

    def run(self):
        """Main monitoring loop."""
        self.running = True
        self._log("Chrome Monitor started")

        poll_interval = self.config.get("poll_interval", 2.0)

        while self.running:
            try:
                chrome = self._find_chrome()

                if chrome:
                    self._check_auto_dismiss(chrome)
                    self._check_watchers(chrome)
                else:
                    if self.config.get("log_elements"):
                        self._log("Chrome not found")

            except Exception as e:
                self._log(f"Error in monitor loop: {e}")

            time.sleep(poll_interval)

        self._log("Chrome Monitor stopped")

    def stop(self):
        """Stop the monitor."""
        self.running = False


def write_pid():
    """Write PID file."""
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))


def read_pid():
    """Read PID from file."""
    try:
        with open(PID_FILE) as f:
            return int(f.read().strip())
    except:
        return None


def remove_pid():
    """Remove PID file."""
    try:
        os.remove(PID_FILE)
    except:
        pass


def is_running():
    """Check if daemon is running."""
    pid = read_pid()
    if pid:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            remove_pid()
    return False


def start_daemon():
    """Start the monitor daemon."""
    if is_running():
        print("Chrome Monitor is already running")
        return

    # Fork to background
    pid = os.fork()
    if pid > 0:
        print(f"Chrome Monitor started (PID: {pid})")
        return

    # Child process
    os.setsid()
    write_pid()

    monitor = ChromeMonitor()

    def signal_handler(signum, frame):
        monitor.stop()
        remove_pid()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    monitor.run()


def stop_daemon():
    """Stop the monitor daemon."""
    pid = read_pid()
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
            print("Chrome Monitor stopped")
            remove_pid()
        except OSError:
            print("Chrome Monitor is not running")
            remove_pid()
    else:
        print("Chrome Monitor is not running")


def status():
    """Check daemon status."""
    if is_running():
        pid = read_pid()
        print(f"Chrome Monitor is running (PID: {pid})")
    else:
        print("Chrome Monitor is not running")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "start":
        start_daemon()
    elif command == "stop":
        stop_daemon()
    elif command == "status":
        status()
    elif command == "run":
        # Run in foreground (for debugging)
        monitor = ChromeMonitor()
        try:
            monitor.run()
        except KeyboardInterrupt:
            monitor.stop()
    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
