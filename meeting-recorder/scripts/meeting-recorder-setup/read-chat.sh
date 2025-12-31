#!/bin/bash
# Read Chat Messages from Google Meet
#
# Uses JavaScript injection via Chrome DevTools to extract chat messages
# Requires the Claude in Chrome MCP to be available
#
# Usage: read-chat.sh [output_file]

set -e

OUTPUT_FILE="${1:-/tmp/meetings/current/chat.json}"
MEETINGS_DIR="/tmp/meetings"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# JavaScript to extract chat messages (from user-provided snippet)
read -r -d '' JS_CODE << 'EOF' || true
(function() {
  const messages = [];
  const seenIds = new Set();

  // Get message containers (the ones with class jO4O1)
  const messageElements = document.querySelectorAll('[data-message-id]');

  messageElements.forEach((el) => {
    const messageId = el.getAttribute('data-message-id');

    // Skip duplicates (the pin button also has data-message-id)
    if (seenIds.has(messageId)) return;

    // Only process the actual message container, not the pin button
    // The container has the jsname="dTKtvb" child with the message text
    const textContainer = el.querySelector('[jsname="dTKtvb"]');
    if (!textContainer) return; // This is probably the pin button, skip it

    seenIds.add(messageId);

    const text = textContainer.textContent?.trim() || '';

    messages.push({
      id: messageId,
      text: text,
    });
  });

  return JSON.stringify(messages, null, 2);
})();
EOF

# Note: This script is a placeholder. Actual JavaScript execution would require:
# 1. Chrome DevTools Protocol connection, or
# 2. Claude in Chrome MCP extension
#
# For now, we'll output a message explaining the limitation

echo -e "${YELLOW}Note: Direct JavaScript execution requires browser integration.${NC}"
echo ""
echo "To read chat messages, you can:"
echo ""
echo "1. Use Chrome DevTools Console:"
echo "   - Open Chrome DevTools (F12)"
echo "   - Paste the following JavaScript:"
echo ""
echo "---"
cat << 'JSEOF'
function extractMeetChatMessages() {
  const messages = [];
  const seenIds = new Set();
  const messageElements = document.querySelectorAll('[data-message-id]');

  messageElements.forEach((el) => {
    const messageId = el.getAttribute('data-message-id');
    if (seenIds.has(messageId)) return;
    const textContainer = el.querySelector('[jsname="dTKtvb"]');
    if (!textContainer) return;
    seenIds.add(messageId);
    messages.push({
      id: messageId,
      text: textContainer.textContent?.trim() || '',
    });
  });

  return messages;
}
console.log(JSON.stringify(extractMeetChatMessages(), null, 2));
JSEOF
echo "---"
echo ""
echo "2. Use Claude in Chrome MCP (if available):"
echo "   - The mcp__claude-in-chrome__javascript_tool can execute this"
echo ""

# If we have xdotool, we could potentially inject via DevTools
# But this is complex and error-prone

exit 0
