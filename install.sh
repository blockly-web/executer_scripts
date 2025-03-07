#!/bin/bash
set -euo pipefail

# Variables - update these to match your GitHub repo details.
REPO_USER="blockly-web"
REPO_NAME="executer_scripts"
RELEASE_TAG="v1.0.2"
SCRIPT_NAME="cli_executer.sh"  # The main script file in the release
INSTALL_DIR="/usr/local/bin"
TARGET_NAME="cli_executer"     # The command name that users will run

# Construct the download URL.
SCRIPT_URL="https://github.com/$REPO_USER/$REPO_NAME/releases/download/$RELEASE_TAG/$SCRIPT_NAME"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: Installation directory does not exist"
    exit 1
fi

# Check for existing installation
if [ -f "$INSTALL_DIR/$TARGET_NAME" ]; then
    read -p "Previous installation found. Override? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Downloading $SCRIPT_NAME from $SCRIPT_URL..."
curl -fsSL "$SCRIPT_URL" -o "$TARGET_NAME"

echo "Making the script executable..."
chmod +x "$TARGET_NAME"

echo "Installing $TARGET_NAME to $INSTALL_DIR (sudo privileges might be required)..."
sudo mv "$TARGET_NAME" "$INSTALL_DIR/"

echo "Installation complete! You can now run '$TARGET_NAME' from anywhere."

