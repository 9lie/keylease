# Keylease

A one-time secret channel for AI agents on macOS.

Agents shouldn’t be handed secrets in chat: they end up in conversation context, logs, and shell history, and agents often ask you to delete them. Injecting an environment variable into an already-running agent is also awkward. Keylease gives you a menu bar action that opens a 10-minute, single-use channel. The agent uses the secret through a child process environment and never reads the value itself.

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
