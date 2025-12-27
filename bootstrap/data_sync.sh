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

# 4. Download & Extract with Fallback
# We use a subshell or simple if/else logic for fallback.
# Check for unzstd availability for the 'nice' tar command.
if command -v unzstd >/dev/null 2>&1; then
    echo "Method: tar --use-compress-program=unzstd"
    # curl -L --fail: fail on HTTP errors (404 etc)
    # pv: progress bar if available, else cat (or skip if not installed, but assumed in apt list)
    if command -v pv >/dev/null 2>&1; then
    echo "Decompression Method: tar --use-compress-program=unzstd"
    TAR_DECOMPRESS_OPT="--use-compress-program=unzstd"
    DECOMPRESS_CMD="cat" # No separate pipe needed, tar handles it
else
    echo "Decompression Method: zstd -dc (fallback)"
    DECOMPRESS_CMD="zstd -dc"
    TAR_DECOMPRESS_OPT="" # tar -x will handle it after zstd -dc
fi

# Determine PV command (for progress bar)
PV_CMD="cat" # Default to cat (no-op)
if command -v pv >/dev/null 2>&1; then
    PV_CMD="pv"
fi

# 4. Download & Extract with Fallback
# Determine Download Method
if [[ "$DATA_URL" == *"drive.google.com"* ]]; then
    echo "Detected Google Drive URL. Using gdown..."
    
    # Ensure gdown is installed
    if ! command -v gdown &>/dev/null; then
        echo "gdown not found. Installing via pip..."
        pip install gdown
    fi

    # Download to temporary file (more robust than stdout for Drive)
    TEMP_ARCHIVE="$TARGET_DIR/temp_dataset.tar.zst"
    echo "Downloading to $TEMP_ARCHIVE..."
    
    if gdown "$DATA_URL" -O "$TEMP_ARCHIVE"; then
        echo "Download successful. Extracting..."
        
        # Extract from file
        $PV_CMD "$TEMP_ARCHIVE" \
            | $DECOMPRESS_CMD \
            | tar $TAR_DECOMPRESS_OPT -x -C "$TARGET_DIR"
            
        # Cleanup
        rm -f "$TEMP_ARCHIVE"
    else
        echo "ERROR: gdown failed."
        exit 1
    fi

else
    echo "Detected standard URL. Using curl..."
    # Standard HTTP/HTTPS
    curl -L --fail "$DATA_URL" \
        | $PV_CMD \
        | $DECOMPRESS_CMD \
        | tar $TAR_DECOMPRESS_OPT -x -C "$TARGET_DIR"
fi

# 5. Mark Complete
# Only reached if the commands above succeeded (set -e)
touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
