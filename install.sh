#!/usr/bin/env bash

set -e

echo "=== Setting up scene detection environment ==="

# Homebrew

if ! command -v brew >/dev/null 2>&1; then
echo "Installing Homebrew..."

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

fi

echo "Installing Python..."
brew install python

echo "Installing FFmpeg..."
brew install ffmpeg

mkdir -p "$HOME/bin"

if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"; then
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
fi


echo
echo "Done."
echo
echo "Reload shell:"
echo
echo "source ~/.zshrc"

