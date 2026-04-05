#!/usr/bin/env bash
# Fetch Lua library sources for testing (not vendored — run before tests)
set -euo pipefail

DEPS_DIR="$(dirname "$0")/deps"
mkdir -p "$DEPS_DIR"

# AceSerializer-3.0
if [ ! -f "$DEPS_DIR/AceSerializer-3.0.lua" ]; then
  echo "Fetching AceSerializer-3.0.lua..."
  curl -sL "https://raw.githubusercontent.com/hurricup/WoW-Ace3/master/AceSerializer-3.0/AceSerializer-3.0.lua" \
    -o "$DEPS_DIR/AceSerializer-3.0.lua"
fi

# LibDeflate
if [ ! -f "$DEPS_DIR/LibDeflate.lua" ]; then
  echo "Fetching LibDeflate.lua..."
  curl -sL "https://raw.githubusercontent.com/SafeteeWoW/LibDeflate/main/LibDeflate.lua" \
    -o "$DEPS_DIR/LibDeflate.lua"
fi

# LibSerialize
if [ ! -f "$DEPS_DIR/LibSerialize.lua" ]; then
  echo "Fetching LibSerialize.lua..."
  curl -sL "https://raw.githubusercontent.com/rossnichols/LibSerialize/main/LibSerialize.lua" \
    -o "$DEPS_DIR/LibSerialize.lua"
fi

echo "Dependencies ready in $DEPS_DIR"
