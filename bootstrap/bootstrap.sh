#!/bin/bash
set -e

# --- 0. ROBUSTNESS & LOGGING ---
# Ensure we are executing from the repo root
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

# Log output to file and stdout
LOG_FILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== [bootstrap.sh] Starting Setup @ $(date) ==="
echo "Repo Root: $REPO_ROOT"

# --- 1. PERSISTENCE & MOUNTS ---
# Using absolute path via SCRIPT_DIR
source "$SCRIPT_DIR/mounts.sh"

# --- 2. SYSTEM DEPENDENCIES ---
echo "=== [bootstrap.sh] Checking system dependencies ==="
# Optimized: Only run apt-get if tools are missing
NEEDED_TOOLS=""
if ! command -v tmux &> /dev/null; then NEEDED_TOOLS="$NEEDED_TOOLS tmux"; fi
if ! command -v zstd &> /dev/null; then NEEDED_TOOLS="$NEEDED_TOOLS zstd"; fi
if ! command -v pv &> /dev/null; then NEEDED_TOOLS="$NEEDED_TOOLS pv"; fi
# Always check for common build/GL libs if you want, or trust base image.
# Adding libgl1-mesa-glx just in case for CV tasks.

if [ -n "$NEEDED_TOOLS" ]; then
    echo "Installing missing tools: $NEEDED_TOOLS"
    apt-get update && apt-get install -y $NEEDED_TOOLS libgl1-mesa-glx git curl build-essential
else
    echo "System tools present. Skipping apt-get."
fi

# --- 3. PYTHON ENVIRONMENT (uv + venv) ---
echo "=== [bootstrap.sh] Setting up Python Environment ==="

# PERSISTENT CACHE CONFIG
export UV_CACHE_DIR="/mnt/persist/cache/uv"
export PIP_CACHE_DIR="/mnt/persist/cache/pip"
export HF_HOME="/mnt/persist/cache/huggingface"
export TORCH_HOME="/mnt/persist/cache/torch"

# Install uv if missing
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv &> /dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Source env for current session if created
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
fi

# Create Virtual Environment (Idempotent)
VENV_DIR="$REPO_ROOT/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating venv at $VENV_DIR..."
    uv venv "$VENV_DIR"
else
    echo "venv exists at $VENV_DIR."
fi
source "$VENV_DIR/bin/activate"

# Sync Dependencies
echo "Syncing dependencies..."
if [ -f "uv.lock" ]; then
    echo "Found uv.lock. Syncing frozen..."
    uv sync --frozen
elif [ -f "pyproject.toml" ]; then
    echo "Found pyproject.toml. Syncing..."
    uv sync
elif [ -f "requirements.lock" ]; then
    echo "Found requirements.lock. Installing..."
    uv pip install -r requirements.lock
elif [ -f "requirements.txt" ]; then
    echo "Found requirements.txt. Installing..."
    uv pip install -r requirements.txt
else
    echo "ERROR: No dependency file found (uv.lock, pyproject.toml, requirements.lock/txt)."
    echo "       Cannot proceed with python environment setup."
    exit 1
fi

# --- 4. DATA SYNC ---
# Calls the idempotent data sync script
"$SCRIPT_DIR/data_sync.sh"

# --- 5. POST-SETUP CONFIG ---
echo "=== [bootstrap.sh] Configuring user shell ==="

# Add venv activation code to .bashrc if not present
if ! grep -q "source $VENV_DIR/bin/activate" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto-activate repo venv" >> ~/.bashrc
    echo "source $VENV_DIR/bin/activate" >> ~/.bashrc
    echo "cd $REPO_ROOT" >> ~/.bashrc
fi

# --- 6. DONE ---
echo "=== [bootstrap.sh] Setup Complete @ $(date) ==="
echo "You can now start training."
