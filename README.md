# Claude Skills Collection

A curated collection of [Claude Code](https://claude.ai/code) skills for common development workflows.

## What are Claude Skills?

Skills are reusable instructions that teach Claude how to perform specific tasks. They live in `~/.claude/skills/` and are automatically loaded when relevant. Each skill contains:

- **SKILL.md** - Instructions Claude follows when the skill is triggered
- **REFERENCE.md** - Detailed documentation Claude can consult
- **scripts/** - Helper scripts the skill can execute

## Available Skills

### chrome-automation

Launch and control Chrome in a headless Linux environment using AT-SPI2 accessibility APIs.

**Use case:** Browser automation in dev containers, CI environments, or remote servers where you need to control Chrome programmatically.

**Why AT-SPI2?** Standard tools like `xdotool` don't work reliably with Chrome because Chrome uses its own GPU-accelerated compositor that bypasses X11 input events. AT-SPI2 uses Chrome's accessibility tree instead.

**Features:**
- Launch Chrome with accessibility enabled
- Click buttons, links, and UI elements by name
- Type text and send keyboard shortcuts
- Take screenshots
- Navigate to URLs

#### Installation

**Step 1: Run the setup script**

The setup script installs all dependencies (Chrome, VNC, AT-SPI2 packages) and creates the `chrome-a11y` command:

```bash
# Clone the repo
git clone https://github.com/cevatkerim/claude-skills.git
cd claude-skills

# Run setup (requires root)
sudo ./chrome-automation/scripts/chrome-automation-setup/setup.sh
```

This installs:
- Google Chrome
- TigerVNC + noVNC (for remote display)
- AT-SPI2 accessibility packages
- `chrome-a11y` CLI tool (symlinked to `/usr/local/bin/`)

**Step 2: Copy the skill to Claude**

```bash
cp -r chrome-automation ~/.claude/skills/
```

#### Usage

```bash
# Start VNC + Chrome
start-chrome-automation https://google.com

# Control Chrome
chrome-a11y list                    # List clickable elements
chrome-a11y click "Sign in"         # Click by name
chrome-a11y type "search query"     # Type text
chrome-a11y navigate "https://..."  # Go to URL

# Stop everything
stop-chrome-automation
```

**VNC Access:**
- Direct: `<ip>:5901` (password: `vnc123`)
- Browser: `http://<ip>:6080/vnc.html`

## Creating Your Own Skills

1. Create a directory under `~/.claude/skills/your-skill-name/`
2. Add a `SKILL.md` with frontmatter and instructions
3. Optionally add `REFERENCE.md` for detailed docs
4. Add helper scripts in `scripts/` if needed

Example `SKILL.md` structure:

```markdown
---
name: your-skill-name
description: Brief description of when to use this skill
---

# Skill Name

Instructions for Claude to follow...
```

## Contributing

Feel free to submit PRs with new skills or improvements to existing ones.

## License

MIT
