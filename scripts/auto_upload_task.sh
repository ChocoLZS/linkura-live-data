#!/bin/bash

# Auto upload task script for linkura-motion-cli
# This script downloads linkura-motion-cli and syncs/uploads external_link changes

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/data"
ARCHIVE_JSON="$DATA_DIR/archive.json"

# Tool configuration
TOOL_URL="https://github.com/ChocoLZS/linkura-cli/releases/download/linkura-motion-cli-v1.1.0/linkura-motion-cli-x86_64-unknown-linux-musl.tar.gz"
TOOL_NAME="linkura-motion-cli"

echo "Starting auto upload task..."

# Check required environment variables
if [ -z "$R2_BUCKET" ] || [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ]; then
    echo "Error: Required R2 environment variables not set"
    echo "Please set: R2_BUCKET, R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY"
    exit 1
fi

# Create temporary directory for tool
TEMP_DIR=$(mktemp -d)

echo "Downloading linkura-motion-cli..."
curl -L "$TOOL_URL" -o "$TEMP_DIR/linkura-motion-cli.tar.gz"

echo "Extracting linkura-motion-cli..."
tar -xzf "$TEMP_DIR/linkura-motion-cli.tar.gz" -C "$TEMP_DIR"

# Make the tool executable
chmod +x "$TEMP_DIR/$TOOL_NAME"

echo "Tool downloaded and extracted successfully"

# Get the latest commit diff and extract external_link changes
echo "Analyzing git diff for external_link changes..."

# Use Python to process the diff and extract URLs
TEMP_DIR="$TEMP_DIR" python3 << 'EOF'
import json
import sys
import os
import subprocess

def get_git_diff():
    """Get the git diff for archive.json"""
    result = subprocess.run(['git', 'diff', 'HEAD~1', 'HEAD', '--', 'data/archive.json'],
                              capture_output=True, text=True, check=True, encoding='utf-8')
    return result.stdout

def extract_external_link_changes(diff_text):
    """Extract external_link additions from git diff"""
    external_link_changes = []
    lines = diff_text.split('\n')
    
    for line in lines:
        # Look for added lines with external_link
        if line.startswith('+') and '"external_link"' in line and line.strip() != '+':
            # Extract the external_link value
            if '"external_link": "' in line:
                start = line.find('"external_link": "') + len('"external_link": "')
                end = line.find('"', start)
                if end > start:
                    external_link = line[start:end]
                    # Only process if external_link is not empty
                    if external_link and external_link.strip():
                        # Complete the URL
                        full_url = f"https://assets.link-like-lovelive.app{external_link}"
                        external_link_changes.append(full_url)
    
    return external_link_changes

# Main processing
diff_text = get_git_diff()

if not diff_text:
    print("No git diff found")
    sys.exit(0)

external_link_changes = extract_external_link_changes(diff_text)

if not external_link_changes:
    print("No external_link changes found")
    sys.exit(0)

print(f"Found {len(external_link_changes)} external_link changes")

# Write URLs to a temporary file for the shell script to read
with open(f'{os.environ.get("TEMP_DIR", "/tmp")}/external_link_urls.txt', 'w') as f:
    for url in external_link_changes:
        f.write(url + '\n')

print("URLs written to external_link_urls.txt")
EOF

# Check if URLs were found
if [ ! -f "$TEMP_DIR/external_link_urls.txt" ]; then
    echo "No external_link URLs to process"
    exit 0
fi

# Read URLs and process each one
echo "Processing external_link URLs..."
while IFS= read -r url; do
    if [ -n "$url" ]; then
        # Remove any trailing whitespace/newlines
        url=$(echo "$url" | tr -d '\r\n')
        echo "Syncing URL: $url"
        "$TEMP_DIR/$TOOL_NAME" sync -d "$TEMP_DIR" -c 16 "$url"
    fi
done < "$TEMP_DIR/external_link_urls.txt"

# Upload archive.json
echo "Uploading archive.json..."
"$TEMP_DIR/$TOOL_NAME" upload -p archive -f "$ARCHIVE_JSON" -c 1

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "Auto upload task completed successfully"
