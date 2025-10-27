#!/bin/bash

# Notification task script for external_link changes
# This script monitors git commit diffs for external_link changes and sends notifications

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/data"
ARCHIVE_JSON="$DATA_DIR/archive.json"

echo "Starting notification task..."

# Check required environment variables
if [ -z "$QQ_BOT_URL" ] || [ -z "$GROUP_ID" ] || [ -z "$AUTH_TOKEN" ] || [ -z "$QQ_BOT_HOST" ]; then
    echo "Error: Required environment variables not set"
    echo "Please set: QQ_BOT_URL, GROUP_ID, AUTH_TOKEN, QQ_BOT_HOST"
    exit 1
fi

echo "Analyzing git diff for external_link changes..."

# Use Python to process the diff and find external_link changes
python3 << 'EOF'
import json
import sys
import os
import subprocess
import base64

# No longer need requests, urllib3, or ssl since we're using curl

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
                    # Only notify if external_link is not empty
                    if external_link and external_link.strip():
                        external_link_changes.append(external_link)
    
    return external_link_changes

def load_archive_data():
    """Load archive.json data"""
    try:
        with open('data/archive.json', 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading archive.json: {e}")
        return []

def find_entries_by_external_link(archive_data, external_links):
    """Find entries in archive data by external_link"""
    found_entries = []
    
    for external_link in external_links:
        for entry in archive_data:
            if entry.get('external_link') == external_link:
                found_entries.append(entry)
                break
    
    return found_entries

def download_image_as_base64(image_url):
    """Download image and convert to base64 using curl"""
    try:
        # Use curl to download the image with SSL verification disabled
        curl_cmd = [
            'curl',
            '-k',  # Disable SSL certificate verification
            '-s',  # Silent mode
            '-L',  # Follow redirects
            '--max-time', '10',
            image_url
        ]
        
        result = subprocess.run(curl_cmd, capture_output=True, timeout=15)
        
        if result.returncode == 0 and result.stdout:
            # Convert to base64
            image_data = base64.b64encode(result.stdout).decode('utf-8')
            return f"base64://{image_data}"
        else:
            print(f"Error downloading image: curl returned code {result.returncode}")
            return None
    except Exception as e:
        print(f"Error downloading image {image_url}: {e}")
        return None

def create_notification_message(entry):
    """Create notification message for an entry"""
    title = entry.get('name', 'Unknown Title')
    description = entry.get('description', '')
    external_link = entry.get('external_link', '')
    thumbnail_url = entry.get('thumbnail_image_url', '')
    
    # Create text segment
    text_content = f"title: {title}\n\ndescription:{description}\n\nreplay: https://assets.link-like-lovelive.app{external_link}"
    
    message_segments = [
        {
            "type": "text",
            "data": {
                "text": text_content
            }
        }
    ]
    
    # Add image segment if thumbnail exists
    if thumbnail_url:
        base64_image = download_image_as_base64(thumbnail_url)
        if base64_image:
            message_segments.append({
                "type": "image",
                "data": {
                    "file": base64_image
                }
            })
    
    return message_segments

def send_notification(message_segments):
    """Send notification via API using curl"""
    url = os.environ.get('QQ_BOT_URL')
    host = os.environ.get('QQ_BOT_HOST')
    group_id = os.environ.get('GROUP_ID')
    token = os.environ.get('AUTH_TOKEN')

    if not all([url, host, group_id, token]):
        print("Error: Missing required environment variables")
        return False
    
    payload = {
        "group_id": group_id,
        "message": message_segments
    }
    
    # Convert payload to JSON string
    payload_json = json.dumps(payload)
    
    # Use curl to send the request with SSL verification disabled
    curl_cmd = [
        'curl',
        '-k',  # Disable SSL certificate verification
        '-X', 'POST',
        f'{url}/send_group_msg',
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/json',
        '-H', f'Host: {host}',
        '-d', payload_json,
        '--max-time', '30'
    ]
    
    try:
        result = subprocess.run(curl_cmd, capture_output=True, text=True, timeout=35)
        
        if result.returncode == 0:
            print(f"Notification sent successfully")
            print(f"Response: {result.stdout}")
            return True
        else:
            print(f"Error sending notification: curl returned code {result.returncode}")
            print(f"stderr: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"Error sending notification: Request timeout")
        return False
    except Exception as e:
        print(f"Error sending notification: {e}")
        return False

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

archive_data = load_archive_data()
if not archive_data:
    print("No archive data found")
    sys.exit(1)

entries_to_notify = find_entries_by_external_link(archive_data, external_link_changes)

if not entries_to_notify:
    print("No entries found for notification")
    sys.exit(0)

print(f"Sending notifications for {len(entries_to_notify)} entries")

for entry in entries_to_notify:
    print(f"Processing entry: {entry.get('name', 'Unknown')}")
    message_segments = create_notification_message(entry)
    
    if send_notification(message_segments):
        print(f"Successfully sent notification for: {entry.get('name', 'Unknown')}")
    else:
        print(f"Failed to send notification for: {entry.get('name', 'Unknown')}")

print("Notification task completed")
EOF

echo "Notification task completed successfully"