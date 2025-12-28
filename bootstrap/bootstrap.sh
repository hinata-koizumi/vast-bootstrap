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

# --- Ensure system tools (no venv dependency) ---

# unzip
if ! command -v unzip >/dev/null 2>&1; then
  apt-get update
  apt-get install -y unzip
fi

# gdown (system-level install)
if ! command -v gdown >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    # IMPORTANT: avoid venv requirement
    uv pip install --system gdown
  else
    python3 -m pip install --upgrade pip
    python3 -m pip install gdown
  fi
fi

TMP_ZIP="$(mktemp -p "$TARGET_DIR" dataset.XXXXXX.zip)"
echo "Downloading ZIP to $TMP_ZIP"
gdown --fuzzy "$DATA_URL" -O "$TMP_ZIP"

echo "Extracting ZIP..."
unzip -oq "$TMP_ZIP" -d "$TARGET_DIR"
rm -f "$TMP_ZIP"

# Mac junk cleanup (inside dataset folder)
rm -rf "$TARGET_DIR/__MACOSX"
find "$TARGET_DIR" -name ".DS_Store" -delete || true

touch "$SENTINEL"
echo "SUCCESS: Data sync completed."
