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

# 4. Configure Extraction Tools
# Determine whether to use zstd pipe or tar's internal option
if command -v unzstd >/dev/null 2>&1; then
    echo "Decompression Method: tar --use-compress-program=unzstd"
    TAR_DECOMPRESS_OPT="--use-compress-program=unzstd"
    DECOMPRESS_CMD="cat" # Pass through (no-op)
else
    echo "Decompression Method: zstd -dc (fallback)"
    TAR_DECOMPRESS_OPT="" 
    DECOMPRESS_CMD="zstd -dc"
fi

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

    # Download to temporary file
    TEMP_ARCHIVE="$TARGET_DIR/temp_dataset.tar.zst"
    echo "Downloading to $TEMP_ARCHIVE..."
    
    if gdown "$DATA_URL" -O "$TEMP_ARCHIVE"; then
        echo "Download successful. Extracting..."
        
        # Extract logic: 
        # file -> pv -> [zstd -dc] -> tar [opts]
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
    # Curl stream: curl -> pv -> [zstd -dc] -> tar [opts]
    curl -L --fail "$DATA_URL" \
        | $PV_CMD \
        | $DECOMPRESS_CMD \
        | tar $TAR_DECOMPRESS_OPT -x -C "$TARGET_DIR"
fi

# 5. Mark Complete
# Only reached if the commands above succeeded (set -e)
touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
