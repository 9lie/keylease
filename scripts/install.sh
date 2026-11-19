#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Keylease.app"

if [ ! -d "$APP" ]; then
  "$ROOT/scripts/build.sh"
fi

if pgrep -x Keylease >/dev/null 2>&1; then
  killall Keylease 2>/dev/null || true
  sleep 1
fi

rm -rf "/Applications/Keylease.app"
cp -R "$APP" "/Applications/Keylease.app"

if [ -w /usr/local/bin ]; then
  cp "$BUILD/keylease" /usr/local/bin/keylease
  chmod +x /usr/local/bin/keylease
  BIN_DIR="/usr/local/bin"
else
  mkdir -p "$HOME/.local/bin"
  cp "$BUILD/keylease" "$HOME/.local/bin/keylease"
  chmod +x "$HOME/.local/bin/keylease"
  BIN_DIR="$HOME/.local/bin"
fi

open "/Applications/Keylease.app"

mkdir -p "$HOME/.codex/skills/keylease" "$HOME/.agents/skills/keylease"
cp "$ROOT/skill/SKILL.md" "$HOME/.codex/skills/keylease/SKILL.md"
cp "$ROOT/skill/SKILL.md" "$HOME/.agents/skills/keylease/SKILL.md"

echo "Installed:"
echo "  /Applications/Keylease.app"
echo "  $BIN_DIR/keylease"
echo "  $HOME/.codex/skills/keylease/SKILL.md"
echo "  $HOME/.agents/skills/keylease/SKILL.md"
if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
  echo "Add $BIN_DIR to your PATH to use the keylease command."
fi
