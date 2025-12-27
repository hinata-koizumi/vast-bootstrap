#!/bin/bash
# bootstrap/healthcheck.sh

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "=== HEALTHCHECK ==="

FAIL=0

# 1. Check Mount
if mountpoint -q /mnt/persist; then
    echo "[OK] /mnt/persist is mounted."
else
    echo "[WARN] /mnt/persist is NOT a mountpoint (using local fallback?)."
    # Not a fatal error for functionality, but good to know
fi

# 2. Check Data
SENTINEL=$(find ~/datasets -name ".complete" 2>/dev/null | head -n 1)
if [ -n "$SENTINEL" ]; then
    echo "[OK] Dataset found: $SENTINEL"
else
    echo "[FAIL] Dataset sentinel missing."
    FAIL=1
fi

# 3. Check Python
source "$REPO_ROOT/.venv/bin/activate"
if python -c "import torch; print(f'Torch: {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>/dev/null; then
    echo "[OK] Python environment functional."
else
    echo "[FAIL] Python/Torch check failed."
    FAIL=1
fi

# 4. Check Services
if tmux has-session -t main 2>/dev/null; then
    echo "[OK] Tmux session 'main' is running."
    
    # Check if ports are actually listening
    if command -v ss &>/dev/null; then
        # Jupyter (8888)
        if ss -ltn | grep -q ":8888 "; then 
            echo "[OK] Jupyter listening on :8888"
        else 
            echo "[WARN] Jupyter port :8888 NOT listening. Check logs: ~/logs/jupyter.log"
        fi
        
        # TensorBoard (6006)
        if ss -ltn | grep -q ":6006 "; then 
            echo "[OK] TB listening on :6006"
        else 
            echo "[WARN] TB port :6006 NOT listening. Check logs: ~/logs/tensorboard.log"
        fi
    fi
else
    echo "[INFO] No active tmux session (start_services.sh not run?)."
fi

echo "-------------------"
if [ "$FAIL" -eq 0 ]; then
    echo "STATUS: READY"
    exit 0
else
    echo "STATUS: NOT READY"
    exit 1
fi
