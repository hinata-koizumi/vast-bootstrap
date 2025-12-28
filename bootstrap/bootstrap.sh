#!/bin/bash
set -euo pipefail

DATASET_NAME="${DATASET_NAME:-NYUv2}"
TARGET_DIR="$HOME/datasets/$DATASET_NAME"
SENTINEL="$TARGET_DIR/.complete"

echo "=== [data_sync.sh] Checking data ($DATASET_NAME) ==="

if [ -z "${DATA_URL:-}" ]; then
  echo "ERROR: DATA_URL is not set."
  exit 1
fi

mkdir -p "$TARGET_DIR"

if [ -f "$SENTINEL" ]; then
  echo "SUCCESS: Data already present ($SENTINEL found)."
  exit 0
fi

# gdown
if ! command -v gdown >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv pip install gdown
  else
    python -m pip install --upgrade pip
    python -m pip install gdown
  fi
fi

# unzip
if ! command -v unzip >/dev/null 2>&1; then
  apt-get update
  apt-get install -y unzip
fi

TMP_ZIP="$(mktemp -p "$TARGET_DIR" dataset.XXXXXX.zip)"
echo "Downloading ZIP to $TMP_ZIP"
gdown --fuzzy "$DATA_URL" -O "$TMP_ZIP"

echo "Extracting ZIP..."
unzip -oq "$TMP_ZIP" -d "$TARGET_DIR"
rm -f "$TMP_ZIP"

# Mac junk cleanup
rm -rf "$TARGET_DIR/__MACOSX" "$TARGET_DIR/.DS_Store"

touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
