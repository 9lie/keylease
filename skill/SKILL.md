---
name: keylease
description: Use when the user needs to give the agent a secret, API key, token, or credential without pasting it into chat, or when a command needs a secret via Keylease. Guides the user to copy the secret to the clipboard and open a temporary Keylease channel, then injects the secret into a child process with `keylease run --env NAME -- command`. Never ask the user to paste the secret into the conversation.
---

# Keylease

Keylease gives the agent a **temporary secret channel**. The channel is temporary; the secret itself may not be. The user may simply not want it in the chat and may later ask you to save it somewhere.

The app lives at `/Applications/Keylease.app`; the CLI is `/usr/local/bin/keylease`.

## When to use

- The user needs to give you an API key, token, password, private key, or any credential that should not be pasted into chat.
- A command needs a secret, but the value must not appear in your context, logs, or command arguments.
- The user says things like “here’s a key”, “run this with my token”, or “don’t make me send the secret to you”.

## Standard flow

1. First try the command directly:

```bash
keylease run --env <ENV_NAME> -- <command>
```

If it returns `No active channel`, **do not stop and wait for the user to reply**. Rerun it in wait mode:

```bash
keylease run --wait --env <ENV_NAME> -- <command>
```

It blocks in the background for up to 10 minutes by default. As soon as the user copies the secret to the clipboard and opens the channel, the command runs automatically. The user does not need to send a “ready” message.

2. The first time the user needs to open a channel, use this reminder. Do not ask for the secret itself:

> Copy the secret to your clipboard, then click the key icon in the menu bar (or press `⇧⌘K`). With the panel open, `⌘V` also activates it. You don’t need to send it to me.

If the user cannot find the icon:

```bash
open /Applications/Keylease.app
keylease show
```

3. The command will run automatically once the channel is open. Do not ask for the secret value, do not ask the user to confirm it, and do not say “tell me when it’s open”.

If your tool has a per-call timeout, use `--timeout 2m` and rerun `keylease run --wait ...` after it times out. Do not fall back to repeatedly asking the user.

## You choose the variable name

The name after `--env` is chosen by the agent based on the target tool; the user does not need to name it. Common examples:

```bash
keylease run --env OPENAI_API_KEY -- python app.py
keylease run --env GITHUB_TOKEN -- gh pr list
keylease run --env ANTHROPIC_API_KEY -- claude ...
keylease run --env AWS_SECRET_ACCESS_KEY -- aws ...
```

Without `--env`, the default variable is `KEYLEASE_SECRET`.

To wait for a channel without running a command:

```bash
keylease wait --timeout 10m
```

It exits 0 when a channel is open and non-zero on timeout.

If the tool needs multiple variables, map them inside one shell command:

```bash
keylease run --env KEYLEASE_SECRET -- sh -c 'OPENAI_API_KEY=$KEYLEASE_SECRET exec python app.py'
```

Keylease holds only one secret at a time. For multiple different secrets, ask the user to open a separate channel for each, or use the user’s preferred secret manager.

## Channel rules

- Default lifetime: 10 minutes.
- Single use: each `keylease run` consumes the channel.
- Because there is only one use, **batch all steps that need the secret into one command or script**. Do not run `keylease run` once and then again for a second step.
- Exiting the app also closes the channel.
- The user can close it from the menu bar panel or with `keylease revoke`.

If the channel has expired or was already used, ask the user to copy the secret and reopen it.

## Don’t

- Don’t ask the user to paste the secret into chat.
- Don’t use `keylease set` unless the user explicitly wants a stdin/script setup; the normal flow is the menu bar button.
- Don’t run `echo $OPENAI_API_KEY`, `printenv`, `env`, `cat`, or similar commands to “verify” the secret.
- Don’t write the secret to logs, commits, issues, PRs, chat messages, or unrelated network requests.
- Don’t put the secret value in command-line arguments; let the tool read it from the environment.
- `[REDACTED]` is not the secret and not a failure: the app redacted it in output. Don’t warn the user that the secret leaked, and don’t ask them to rotate it.

## Saving the secret

If the user explicitly asks you to “save this secret somewhere”, you may write it while the channel is valid, for example to a user-specified config file, password manager, or CI secret. A closed channel does not mean the secret must be discarded; whether to keep it is the user’s decision. Do not echo the secret in chat afterwards.

## Boundary

This is not a hard boundary against a malicious agent. A process running as the same user can still call `keylease run` and try to encode the value out. Keylease protects against secrets accidentally entering chat, logs, shell history, and model context. For stronger isolation, suggest per-use confirmation, a command allowlist, or a dedicated secret manager.
