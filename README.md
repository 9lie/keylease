# Keylease

A one-time secret channel for AI agents on macOS.

Copy a secret, press `⇧⌘K`, and let an agent use it without pasting it into chat. The secret stays in app memory, expires after 10 minutes, and can be used once. The app injects it into the child process, so the CLI never reads the value.

## Install

Requires macOS 14+ and Xcode Command Line Tools.

```bash
git clone https://github.com/9lie/keylease.git
cd keylease
./scripts/install.sh
```

This installs the app, the `keylease` CLI, and the agent skill, then opens the app.

## Use

1. Copy the secret to the clipboard.
2. Press `⇧⌘K`, or click the key icon and choose **Open from clipboard (⌘V)**.
3. Tell the agent to run:

```bash
keylease run --env OPENAI_API_KEY -- python app.py
```

If no channel is open yet, use wait mode:

```bash
keylease run --wait --env OPENAI_API_KEY -- python app.py
```

It waits up to 10 minutes and starts as soon as you open the channel.

Press `Esc` to close the panel. A channel can be used once, so batch multi-step work into one command. To map multiple variables:

```bash
keylease run --env KEYLEASE_SECRET -- sh -c 'OPENAI_API_KEY=$KEYLEASE_SECRET exec python app.py'
```

## Commands

| Command | What it does |
| --- | --- |
| `keylease run --env NAME -- <command>` | Run with the open channel |
| `keylease run --wait --env NAME -- <command>` | Wait for a channel, then run |
| `keylease wait` | Wait for a channel only |
| `keylease revoke` | Close the channel |
| `keylease show` | Open the menu panel |

Without `--env`, the variable is `KEYLEASE_SECRET`.
