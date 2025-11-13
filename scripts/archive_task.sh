#!/bin/bash

# Archive task script for linkura-cli
# This script downloads linkura-cli, runs the archive command, and processes the results

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/data"
ARCHIVE_JSON="$DATA_DIR/archive.json"
ARCHIVE_DETAILS_JSON="$DATA_DIR/archive-details.json"
TEMP_ARCHIVE="/tmp/archive.json"

# Tool URL and configuration
TOOL_URL="https://github.com/ChocoLZS/linkura-cli/releases/download/linkura-cli-v0.0.9/linkura-cli-x86_64-unknown-linux-musl"
TOOL_NAME="linkura-cli"

echo "Starting archive task..."

# Create temporary directory for tool
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading linkura-cli..."
curl -L "$TOOL_URL" -o linkura-cli


# Make the tool executable
chmod +x ./$TOOL_NAME

echo "Running archive command..."
./$TOOL_NAME --player-id "$PLAYER_ID" --password "$PASSWORD" api -s "$TEMP_ARCHIVE" archive -l 6

# Check if temp archive was created
if [ ! -f "$TEMP_ARCHIVE" ]; then
    echo "Error: Archive command did not create output file"
    exit 1
fi

echo "Processing archive data..."

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# If archive.json doesn't exist, create it with empty array
if [ ! -f "$ARCHIVE_JSON" ]; then
    echo "[]" > "$ARCHIVE_JSON"
fi

# Use Python to process the JSON files
TEMP_ARCHIVE=$TEMP_ARCHIVE ARCHIVE_JSON=$ARCHIVE_JSON ARCHIVE_DETAILS_JSON=$ARCHIVE_DETAILS_JSON TEMP_DIR=$TEMP_DIR TOOL_NAME=$TOOL_NAME python3 << 'EOF'
import json
import sys
import os
import subprocess

def load_json(file_path):
    """Load JSON from file, return empty list if file doesn't exist or is invalid"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []

def save_json(data, file_path):
    """Save JSON data to file"""
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def normalize_archive_entry(entry):
    """Normalize archive entry to match the expected format"""
    # Define expected fields based on the backup data
    expected_fields = [
        "archives_id", "description", "external_link", "live_end_time",
        "live_id", "live_start_time", "live_type", "name", 
        "thumbnail_image_url", "video_url"
    ]
    
    # Create normalized entry with only expected fields
    normalized = {}
    for field in expected_fields:
        normalized[field] = entry.get(field, "")
    
    return normalized

def find_new_data(temp_data, existing_data):
    """Find entries with new video_url or external_link data"""
    existing_dict = {entry['archives_id']: entry for entry in existing_data if 'archives_id' in entry}
    new_entries = []
    updated_entries = []
    
    for temp_entry in temp_data:
        if 'archives_id' not in temp_entry:
            continue
            
        archives_id = temp_entry['archives_id']
        # normalized_temp = normalize_archive_entry(temp_entry)
        normalized_temp = temp_entry
        
        if archives_id in existing_dict:
            existing_entry = existing_dict[archives_id]
            has_updates = False
            
            # Check video_url
            if (existing_entry.get('video_url', '') == '' and 
                normalized_temp.get('video_url', '') != ''):
                has_updates = True
                
            # Check external_link
            if (existing_entry.get('external_link', '') == '' and 
                normalized_temp.get('external_link', '') != ''):
                has_updates = True
                
            if has_updates:
                # Update existing entry with new data
                for key, value in normalized_temp.items():
                    if value != '' or existing_entry.get(key, '') == '':
                        existing_entry[key] = value
                updated_entries.append(archives_id)
        else:
            # New entry
            new_entries.append(normalized_temp)
    
    return new_entries, updated_entries

def get_archive_details(live_id, live_type, tool_path, temp_file):
    """Get archive details for a specific live_id and live_type"""
    try:
        # Run the linkura-cli command to get archive details
        command = [tool_path, "-k", "api", "-s", temp_file, "archive-details", "-i", live_id, "-t", str(live_type)]
        result = subprocess.run(command, capture_output=True, text=False, cwd=os.environ.get('TEMP_DIR', '.'))
        
        if result.returncode == 0:
            # Try to load the result from temp file
            try:
                with open(temp_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error reading temp file {temp_file}: {e}")
                return None
        else:
            print(f"Error getting archive details for {live_id}: {result.returncode}")
            return None
    except Exception as e:
        print(f"Exception getting archive details for {live_id}: {e}")
        return None

def process_archive_details(detail_data):
    """Process archive details by clearing specific array fields"""
    if detail_data:
        detail_data['gift_pt_rankings'] = []
        detail_data['timelines'] = []
        prefix_to_remove = 'https://assets.link-like-lovelive.app'
        if 'video_url' in detail_data and detail_data['video_url']:
            if detail_data['video_url'].startswith(prefix_to_remove):
                detail_data['video_url'] = detail_data['video_url'][len(prefix_to_remove):]
        if 'archive_url' in detail_data and detail_data['archive_url']:
            if detail_data['archive_url'].startswith(prefix_to_remove):
                detail_data['archive_url'] = detail_data['archive_url'][len(prefix_to_remove):]
    return detail_data

def update_archive_details_json(new_entries, existing_archive_details, tool_path):
    """Update archive-details.json with new entries"""
    temp_file = "/tmp/archive_detail_temp.json"
    updated_count = 0
    
    for entry in new_entries:
        live_id = entry.get('live_id')
        live_type = entry.get('live_type')
        
        if not live_id or live_type is None:
            continue
            
        # Skip if already exists in archive-details
        if live_id in existing_archive_details:
            continue
            
        print(f"Getting archive details for {live_id} (type: {live_type})")
        detail_data = get_archive_details(live_id, live_type, tool_path, temp_file)
        
        if detail_data:
            # Process the detail data
            processed_data = process_archive_details(detail_data)
            existing_archive_details[live_id] = processed_data
            updated_count += 1
            print(f"Added archive details for {live_id}")
        else:
            print(f"Failed to get archive details for {live_id}")
    
    return updated_count

# Main processing
temp_archive = os.environ.get('TEMP_ARCHIVE', '/tmp/archive.json')
archive_json = os.environ.get('ARCHIVE_JSON', 'data/archive.json')
archive_details_json = os.environ.get('ARCHIVE_DETAILS_JSON', 'data/archive-details.json')
temp_dir = os.environ.get('TEMP_DIR', '.')
tool_name = os.environ.get('TOOL_NAME', 'linkura-cli')
tool_path = os.path.join(temp_dir, tool_name)

print(f"Loading temp archive from: {temp_archive}")
print(f"Loading existing archive from: {archive_json}")

temp_data = load_json(temp_archive)
existing_data = load_json(archive_json)

# Load existing archive-details data
existing_archive_details = {}
try:
    with open(archive_details_json, 'r', encoding='utf-8') as f:
        existing_archive_details = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    existing_archive_details = {}

# Remove URL prefix from temp_data
prefix_to_remove = 'https://assets.link-like-lovelive.app'
for entry in temp_data:
    # Process video_url field
    if 'video_url' in entry and entry['video_url']:
        if entry['video_url'].startswith(prefix_to_remove):
            entry['video_url'] = entry['video_url'][len(prefix_to_remove):]
    
    # Process external_link field
    if 'external_link' in entry and entry['external_link']:
        if entry['external_link'].startswith(prefix_to_remove):
            entry['external_link'] = entry['external_link'][len(prefix_to_remove):]

print(f"Temp data entries: {len(temp_data)}")
print(f"Existing data entries: {len(existing_data)}")

new_entries, updated_entries = find_new_data(temp_data, existing_data)

if new_entries or updated_entries:
    print(f"Found {len(new_entries)} new entries and {len(updated_entries)} updated entries")
    
    # Add new entries to existing data
    existing_data.extend(new_entries)
    
    # Sort all data by live_start_time in descending order (newest first)
    existing_data.sort(key=lambda x: x.get('live_start_time', ''), reverse=True)
    
    # Save updated data
    save_json(existing_data, archive_json)
    
    # Update archive-details.json for new entries
    print("Updating archive-details.json...")
    details_updated = update_archive_details_json(new_entries, existing_archive_details, tool_path)
    
    if details_updated > 0:
        # Sort archive-details by live_start_time in descending order
        sorted_details = {}
        items = list(existing_archive_details.items())
        items.sort(key=lambda x: x[1].get('live_start_time', ''), reverse=True)
        for key, value in items:
            sorted_details[key] = value
        
        # Save updated archive-details
        with open(archive_details_json, 'w', encoding='utf-8') as f:
            json.dump(sorted_details, f, ensure_ascii=False, indent=2)
        
        print(f"Updated archive-details.json with {details_updated} new entries")
    
    # Set flag for git operations
    with open('/tmp/has_updates', 'w') as f:
        f.write('true')
    
    print("Archive data updated and sorted successfully")
else:
    print("No new data found")
    with open('/tmp/has_updates', 'w') as f:
        f.write('false')
EOF

echo "Archive task completed successfully"