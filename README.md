# Keylease

A one-time secret channel for AI agents on macOS.

The secret stays in app memory, expires after 10 minutes, and can be used once.

## For humans

1. Copy the secret to the clipboard.
2. Press `⇧⌘K`, or click the key icon in the menu bar and choose **Open from clipboard (⌘V)**.
3. Let the agent run its command.

Press `Esc` to close the panel.

## For agents

To install Keylease, run:

```bash
git clone https://github.com/9lie/keylease.git
cd keylease
./scripts/install.sh
```

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

The installer builds and installs the app and CLI, installs the `keylease` skill, and opens the app. Usage is described in that skill.
