#!/bin/bash
set -euo pipefail

echo "=== [bootstrap.sh] Starting Setup @ $(date -u) ==="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
echo "Repo Root: $REPO_ROOT"

# -----------------------------
# 0) System deps (minimum)
# -----------------------------
echo "=== [bootstrap.sh] Checking system dependencies ==="
export DEBIAN_FRONTEND=noninteractive

need_install=()
for cmd in curl git unzip file pv zstd; do
  command -v "$cmd" >/dev/null 2>&1 || need_install+=("$cmd")
done

if [ "${#need_install[@]}" -gt 0 ]; then
  echo "Installing missing tools: ${need_install[*]}"
  apt-get update
  apt-get install -y "${need_install[@]}"
else
  echo "System tools present. Skipping apt-get."
fi

# -----------------------------
# 1) Install uv (system-level, once per instance)
# -----------------------------
echo "=== [bootstrap.sh] Ensuring uv is installed ==="
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

uv --version || true

# -----------------------------
# 2) Create venv if missing
# -----------------------------
echo "=== [bootstrap.sh] Ensuring venv exists ==="
if [ ! -d ".venv" ]; then
  echo "Creating venv at $REPO_ROOT/.venv ..."
  uv venv .venv
else
  echo "venv exists at $REPO_ROOT/.venv."
fi

# Activate venv for current shell (optional but convenient)
# NOTE: scripts called below should not rely on activation; we ensure PATH anyway.
# shellcheck disable=SC1091
source .venv/bin/activate

echo "Python: $(python -V)"
echo "Pip (venv): $(python -m pip -V || echo 'pip not found (will be installed by uv pip)')"

# -----------------------------
# 3) Sync python deps (lock file or requirements)
# -----------------------------
echo "=== [bootstrap.sh] Syncing Python dependencies (venv) ==="
# pip itself & minimal tools
uv pip install --upgrade pip wheel setuptools >/dev/null

# If you later add requirements, this will be used.
if [ -f "requirements.lock" ]; then
  echo "Found requirements.lock. Installing..."
  # requirements.lock が空でも落ちないようにする
  uv pip install -r requirements.lock || true
elif [ -f "requirements.txt" ]; then
  echo "Found requirements.txt. Installing..."
  uv pip install -r requirements.txt
else
  echo "No requirements file found. Skipping."
fi

# -----------------------------
# 4) Mount / persistence setup (your existing script)
# -----------------------------
if [ -f "bootstrap/mounts.sh" ]; then
  echo "=== [bootstrap.sh] Running mounts.sh ==="
  bash bootstrap/mounts.sh
fi

# -----------------------------
# 5) Data sync (must run inside a ready venv)
# -----------------------------
echo "=== [bootstrap.sh] Running data sync ==="
# data_sync.sh が uv/gdown/unzip を使う前提でも、
# ここまでで uv と .venv があるので確実に動く
bash bootstrap/data_sync.sh

# -----------------------------
# 6) Shell config (optional)
# -----------------------------
if [ -f "bootstrap/shell.sh" ]; then
  echo "=== [bootstrap.sh] Configuring user shell ==="
  bash bootstrap/shell.sh || true
fi

echo "=== [bootstrap.sh] Setup Complete @ $(date -u) ==="
echo "You can now start training."
