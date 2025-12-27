#!/bin/bash
set -e

# --- CONFIGURATION ---
# Defaults to NYUv2, but customizable
DATASET_NAME="${DATASET_NAME:-NYUv2}"
TARGET_DIR="$HOME/datasets/$DATASET_NAME"
SENTINEL="$TARGET_DIR/.complete"

echo "=== [data_sync.sh] Checking data ($DATASET_NAME) ==="

# 1. Validation
if [ -z "$DATA_URL" ]; then
    echo "ERROR: DATA_URL environment variable is not set."
    echo "       Please export DATA_URL='https://...' before running."
    exit 1
fi

# 2. Check Sentinel
if [ -f "$SENTINEL" ]; then
    echo "SUCCESS: Data already present ($SENTINEL found)."
    exit 0
fi

# 3. Preparation & Cleanup
if [ -d "$TARGET_DIR" ]; then
    echo "WARNING: Target directory exists but sentinel is missing."
    echo "         Assuming incomplete download. Syncing again..."
    # We will simply extract over it. tar usually overwrites.
else
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

echo "Downloading from: $DATA_URL"

# 4. Configure Extraction Function
# Robust extraction function that reads from Stdin
extract_stream() {
    # Usage: some_stream | extract_stream
    if command -v unzstd >/dev/null 2>&1; then
        echo "Decompression: tar (unzstd)"
        tar --use-compress-program=unzstd -x -C "$TARGET_DIR" --no-same-owner
    else
        echo "Decompression: zstd pipe"
        zstd -dc | tar -x -C "$TARGET_DIR" --no-same-owner
    fi
}

# Determine PV command
if command -v pv >/dev/null 2>&1; then
    PV_CMD="pv"
else
    PV_CMD="cat"
fi

# 5. Download & Extract
if [[ "$DATA_URL" == *"drive.google.com"* ]]; then
    echo "Detected Google Drive URL. Using gdown..."
    
    # Ensure gdown is installed (use python -m pip for venv safety)
    if ! command -v gdown &>/dev/null; then
        echo "gdown not found. Installing via pip..."
        python -m pip install gdown
    fi

    # Download to temporary file (in target dir to ensure same filesystem)
    # Using mktemp for safety
    TEMP_ARCHIVE=$(mktemp -p "$TARGET_DIR" dataset.XXXXXX.tar.zst)
    echo "Downloading to $TEMP_ARCHIVE..."
    
    if gdown "$DATA_URL" -O "$TEMP_ARCHIVE"; then
        echo "Download successful. Extracting..."
        
        # Extract from file -> pv -> extract_stream
        if $PV_CMD "$TEMP_ARCHIVE" | extract_stream; then
            echo "Extraction successful."
            rm -f "$TEMP_ARCHIVE"
        else
            echo "ERROR: Extraction failed."
            rm -f "$TEMP_ARCHIVE"
            exit 1
        fi
    else
        echo "ERROR: gdown failed."
        rm -f "$TEMP_ARCHIVE"
        exit 1
    fi

else
    echo "Detected standard URL. Using curl..."
    # Curl stream: curl -> pv -> extract_stream
    curl -L --fail "$DATA_URL" \
        | $PV_CMD \
        | extract_stream
fi

# 6. Mark Complete
# Only reached if the commands above succeeded (set -e)
touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
