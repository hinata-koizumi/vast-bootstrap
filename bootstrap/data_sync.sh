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

# ---- deps ----
command -v unzip >/dev/null 2>&1 || {
  apt-get update
  apt-get install -y unzip
}

command -v gdown >/dev/null 2>&1 || {
  if command -v uv >/dev/null 2>&1; then
    uv pip install gdown
  else
    python -m pip install --upgrade pip
    python -m pip install gdown
  fi
}

# ---- download ----
TMP_ZIP="$(mktemp -p "$TARGET_DIR" dataset.XXXXXX.zip)"
echo "Downloading ZIP to $TMP_ZIP"

gdown --fuzzy "$DATA_URL" -O "$TMP_ZIP"

echo "Extracting ZIP..."
unzip -q "$TMP_ZIP" -d "$TARGET_DIR"
rm -f "$TMP_ZIP"

touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
