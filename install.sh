#!/bin/bash
set -euo pipefail

# Define variables
SCRIPT_URL="https://github.com/blockly-web/executer_scripts/releases/download/v1.0.0/cli_executer.sh"
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="cli_executer"

echo "Downloading $SCRIPT_NAME..."
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"

echo "Making the script executable..."
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo "Installation complete! You can now run '$SCRIPT_NAME' from anywhere."


#!/bin/bash
set -euo pipefail

# Variables - update these to match your GitHub repo details.
REPO_USER="blockly-web"
REPO_NAME="executer_scripts"
RELEASE_TAG="v1.0.0"
SCRIPT_NAME="cli_executer.sh"  # The main script file in the release
INSTALL_DIR="/usr/local/bin"
TARGET_NAME="cli_executer"     # The command name that users will run

# Construct the download URL.
SCRIPT_URL="https://github.com/$REPO_USER/$REPO_NAME/releases/download/$RELEASE_TAG/$SCRIPT_NAME"

echo "Downloading $SCRIPT_NAME from $SCRIPT_URL..."
curl -fsSL "$SCRIPT_URL" -o "$TARGET_NAME"

echo "Making the script executable..."
chmod +x "$TARGET_NAME"

echo "Installing $TARGET_NAME to $INSTALL_DIR (sudo privileges might be required)..."
sudo mv "$TARGET_NAME" "$INSTALL_DIR/"

echo "Installation complete! You can now run '$TARGET_NAME' from anywhere."