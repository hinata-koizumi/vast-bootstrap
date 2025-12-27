#!/bin/bash
set -e

# --- CONFIGURATION ---
# --- CONFIGURATION ---
PERSIST_ROOT="${PERSIST_ROOT:-/mnt/persist}"

echo "=== [mounts.sh] persistence setup ==="

# 1. Check for Persistence
if ! mountpoint -q "$PERSIST_ROOT"; then
    echo "WARNING: $PERSIST_ROOT is NOT a mountpoint."
    if [ -d "$PERSIST_ROOT" ]; then
        echo "   Directory exists but not mounted. Using it as local fallback."
    else
        echo "   Directory missing. Creating local fallback directory..."
        mkdir -p "$PERSIST_ROOT"
    fi
else
    echo "SUCCESS: $PERSIST_ROOT is mounted."
fi

# 2. Create Directory Structure in Persist
# We need datasets, checkpoints, and cache dirs
echo "Creating structure in $PERSIST_ROOT..."
mkdir -p "$PERSIST_ROOT/datasets"
mkdir -p "$PERSIST_ROOT/checkpoints"
mkdir -p "$PERSIST_ROOT/cache/uv"
mkdir -p "$PERSIST_ROOT/cache/pip"
mkdir -p "$PERSIST_ROOT/cache/huggingface"
mkdir -p "$PERSIST_ROOT/cache/torch"

# 3. Create Symlinks in User Home
# ~/datasets -> /mnt/persist/datasets
echo "Linking ~/datasets..."
rm -rf ~/datasets  # Remove empty dir if exists from docker image
ln -sfn "$PERSIST_ROOT/datasets" ~/datasets

# ~/checkpoints -> /mnt/persist/checkpoints
echo "Linking ~/checkpoints..."
rm -rf ~/checkpoints
ln -sfn "$PERSIST_ROOT/checkpoints" ~/checkpoints

# ~/.cache -> /mnt/persist/cache (Trickier if ~/.cache exists with content)
# Strategy: Link individual subdirs to be safe, OR link the whole parent if appropriate.
# The plan says ~/.cache -> /mnt/persist/cache (Partial or subdirs)
# Let's link specific heavy hitters to avoid breaking other tools.
echo "Linking cache directories..."
mkdir -p ~/.cache

for tool in uv pip huggingface torch; do
    # Remove existing dir/link in ~/.cache and link to persist
    if [ -e "$HOME/.cache/$tool" ]; then
        # If it's a directory and not a symlink, we might want to move content? 
        # For now, just warn and nuke because we want persist state.
        if [ ! -L "$HOME/.cache/$tool" ]; then
            echo "   Warning: Replacing existing local ~/.cache/$tool with link to persist."
        fi
        rm -rf "$HOME/.cache/$tool"
    fi
    ln -sfn "$PERSIST_ROOT/cache/$tool" "$HOME/.cache/$tool"
done

echo "=== [mounts.sh] complete ==="
