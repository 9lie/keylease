# Keylease

A one-time secret channel for AI agents on macOS.

Copy a secret, press `⇧⌘K` or click the menu bar key, and let an agent use it without pasting it into chat. The secret stays in app memory, expires after 10 minutes, and can be consumed once.

## Features

- Clipboard → menu bar channel. No input field, no naming. Press `⌘V` while the panel is open to activate immediately.
- The agent chooses the environment variable name, e.g. `OPENAI_API_KEY`.
- One use, 10-minute TTL by default.
- `keylease run --wait` blocks until you open the channel, then runs automatically.
- No disk, Keychain, or config persistence.
- No `get` / `list`; the CLI cannot read the secret.
- Best-effort secret redaction in child output.
- Native Swift/AppKit. No daemon, no Electron, no network service.

## How it works

```text
clipboard ──⇧⌘K / menu bar──▶ Keylease.app (memory only, 10 min, 1 use)
                                      │ Unix socket (0600)
                                      ▼
                               keylease CLI
                                      │ spawn + env
                                      ▼
                              your command / agent script
```

During `run`, the secret never passes through CLI arguments, stdin, or stdout. The app injects it into the child environment and streams back redacted output. `keylease set` is a scripting-only exception that reads from stdin.

## Install

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`). Intel and Apple Silicon are supported.

```bash
git clone https://github.com/<your-name>/keylease.git
cd keylease
./scripts/install.sh
```

The installer builds and installs `/Applications/Keylease.app`, puts `keylease` in `/usr/local/bin` (or `~/.local/bin`), installs the agent skill to `~/.codex/skills/keylease/` and `~/.agents/skills/keylease/`, and opens the app. It is ad-hoc signed and not notarized.

## Usage

1. Copy the secret to the clipboard.
2. Press `⇧⌘K`, or click the key icon and choose **Open from clipboard (⌘V)**.
3. Let the agent run its command.

Press `Esc` to close the panel without opening a channel.

```bash
keylease run --env OPENAI_API_KEY -- python app.py
keylease run --wait --env OPENAI_API_KEY -- python app.py   # wait for the channel
```

`--wait` blocks for up to 10 minutes and starts as soon as the channel opens, so you do not need to tell the agent “ready”.

## Commands

| Command | Purpose |
| --- | --- |
| `keylease run --env NAME -- <command>` | Run with the current channel |
| `keylease run --wait --env NAME -- <command>` | Wait for a channel, then run |
| `keylease wait [--timeout 10m]` | Wait only; exit 0 when a channel is open |
| `keylease set [--ttl 10m]` | Read a secret from stdin and open a channel (scripts/tests) |
| `keylease revoke` | Close the channel |
| `keylease show` | Open the menu bar panel |

The default variable is `KEYLEASE_SECRET`. Names must match `^[A-Za-z_][A-Za-z0-9_]*$`.

Only one secret is held at a time, and the channel can be consumed once. Batch multi-step work into one command:

```bash
keylease run --env KEYLEASE_SECRET -- sh -c 'OPENAI_API_KEY=$KEYLEASE_SECRET exec python app.py'
```

## Agent skill

`skill/SKILL.md` tells agents when to use Keylease, how to ask you for a channel, use `--wait`, choose variable names, avoid echoing secrets, and batch multi-step work. The installer copies it to Codex and generic agent skill directories.

A useful prompt:

> When you need a secret, use Keylease: `keylease run --wait --env <NAME> -- <command>`. I’ll open the channel from the menu bar.

## Security

Keylease protects against secrets leaking into chat, logs, shell history, and model context. It is not a hard boundary against a malicious local process.

- Secret is memory-only; the socket is mode `0600`.
- CLI has no `get` / `list`.
- Child output is redacted best-effort.
- Expiry, consumption, revocation, or app exit clears the secret.

Limits: any same-user process can call `keylease run` and try to exfiltrate the value via encoding, files, or network requests; redaction only matches the exact text. Child processes inherit the variable, and the clipboard retains the secret until overwritten. If you ask an agent to save the secret, it can do so while the channel is valid.

## Development

```bash
./scripts/build.sh
./scripts/install.sh

printf 'test-secret' | keylease set --ttl 30s
keylease run --env TEST_SECRET -- sh -c 'echo "VAL=$TEST_SECRET"'   # VAL=[REDACTED]
keylease run --env TEST_SECRET -- true                              # No active channel
```

## Troubleshooting

- **No icon:** `open /Applications/Keylease.app` or `keylease show`; `⇧⌘K` also works.
- **`No active channel`:** the channel is closed or used; copy the secret and press `⇧⌘K` again.
- **Cannot connect:** check `pgrep -x Keylease` and `~/Library/Application Support/Keylease/keylease.sock`.

## Uninstall

```bash
killall Keylease 2>/dev/null || true
rm -rf /Applications/Keylease.app
rm -f /usr/local/bin/keylease
rm -rf ~/.codex/skills/keylease ~/.agents/skills/keylease
rm -rf ~/Library/Application\ Support/Keylease
```

v0.1.0 · macOS only · source build, no prebuilt binaries, no notarization.
