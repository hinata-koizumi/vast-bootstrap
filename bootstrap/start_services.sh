#!/bin/bash
set -e

# --- 0. PREAMBLE ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

# --- 1. CONFIGURATION ---
SESSION_NAME="${TMUX_SESSION:-main}"
AUTO_START="${AUTO_START:-0}"
RESTART_SERVICES="${RESTART_SERVICES:-0}"

# Ports
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
TB_PORT="${TENSORBOARD_PORT:-6006}"

# Logging
LOG_DIR="$HOME/logs"
mkdir -p "$LOG_DIR"

# Commands (Overridable)
# Note: piped to tee for logging inside the run_in_pane function
JUPYTER_CMD="${JUPYTER_CMD:-jupyter lab --ip 0.0.0.0 --port $JUPYTER_PORT --no-browser --allow-root}"
TB_CMD="${TENSORBOARD_CMD:-tensorboard --logdir runs --port $TB_PORT --host 0.0.0.0}"
TRAIN_CMD="${TRAIN_CMD:-}"

# Venv activation path
VENV_ACTIVATE_PATH="$REPO_ROOT/.venv/bin/activate"

echo "=== [start_services.sh] Service Automation ==="

# --- 2. VALIDATION ---
if [ "$AUTO_START" != "1" ]; then
    echo "Skipping service startup (AUTO_START != 1)."
    exit 0
fi

if ! command -v tmux &> /dev/null; then
    echo "ERROR: tmux not found. Cannot start services."
    exit 1
fi

# Check Venv
if [ ! -f "$VENV_ACTIVATE_PATH" ]; then
    echo "ERROR: Virtual environment not found at $VENV_ACTIVATE_PATH"
    exit 1
fi

# Check Ports (Robust Implementation)
check_port_free() {
    local port=$1
    if command -v ss &>/dev/null; then
        # -H: no header, -l: listening, -t: tcp, -n: numeric
        if ss -ltnH "sport = :$port" | grep -q .; then return 1; fi
    elif command -v netstat &>/dev/null; then
        if netstat -ltn | grep -q ":$port "; then return 1; fi
    elif command -v lsof &>/dev/null; then
        if lsof -iTCP:$port -sTCP:LISTEN -P >/dev/null; then return 1; fi
    else
        echo "WARN: No port checking tool (ss, netstat, lsof) found. Assuming port $port is free."
        return 0
    fi
    return 0
}

if ! check_port_free "$JUPYTER_PORT"; then
    echo "ERROR: Jupyter port $JUPYTER_PORT is already in use."
    exit 1
fi

if ! check_port_free "$TB_PORT"; then
    echo "ERROR: TensorBoard port $TB_PORT is already in use."
    exit 1
fi

# --- 3. IDEMPOTENCY CHECK ---
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    if [ "$RESTART_SERVICES" == "1" ]; then
        echo "Session '$SESSION_NAME' exists. RESTART_SERVICES=1, killing it..."
        tmux kill-session -t "$SESSION_NAME"
    else
        echo "Session '$SESSION_NAME' already exists. Skipping startup."
        echo "To attach: tmux attach -t $SESSION_NAME"
        exit 0
    fi
fi

# --- 4. STARTUP LOGIC ---
echo "Starting new tmux session: $SESSION_NAME"

# Ensure TensorBoard logdir exists
mkdir -p "$REPO_ROOT/runs"
# Directory for runner scripts
mkdir -p "$LOG_DIR/runners"

# Helper to run command safely in a pane
# Usage: run_in_pane <pane_target> <cmd_string> <log_file>
run_in_pane() {
    local pane=$1
    local cmd=$2
    local log=$3
    
    # Create a temporary runner script
    # This avoids complex quoting issues with tmux send-keys
    local runner_script="$LOG_DIR/runners/run_$(date +%s%N)_${pane//[:.]/_}.sh"
    
    echo "Creating runner script: $runner_script"
    
    cat > "$runner_script" <<EOF
#!/bin/bash
set -e
cd "$REPO_ROOT"
source "$VENV_ACTIVATE_PATH"
echo "=== Starting Command @ \$(date) ==="
$cmd 2>&1 | tee -a "$log"
EOF

    chmod +x "$runner_script"
    
    # Send the execution command to tmux
    tmux send-keys -t "$pane" "bash \"$runner_script\"" C-m
}

# Create session detached, naming window 0 'dev'
tmux new-session -d -s "$SESSION_NAME" -n 'dev'
# Set remain-on-exit to keep panes open if command fails (debugging)
tmux set-option -t "$SESSION_NAME" remain-on-exit on

# Pane 0: Jupyter
echo "   Starting Jupyter on port $JUPYTER_PORT..."
run_in_pane "${SESSION_NAME}:dev.0" "$JUPYTER_CMD" "$LOG_DIR/jupyter.log"

# Pane 1: TensorBoard
echo "   Starting TensorBoard on port $TB_PORT..."
tmux split-window -v -t "${SESSION_NAME}:dev"
run_in_pane "${SESSION_NAME}:dev.1" "$TB_CMD" "$LOG_DIR/tensorboard.log"

# Fix layout
tmux select-layout -t "${SESSION_NAME}:dev" even-vertical

# Window 1: Training (Optional)
if [ -n "$TRAIN_CMD" ]; then
    echo "   Starting Training command..."
    tmux new-window -t "$SESSION_NAME" -n 'train'
    run_in_pane "${SESSION_NAME}:train" "$TRAIN_CMD" "$LOG_DIR/train.log"
else
    echo "   No TRAIN_CMD set. Skipping training window."
fi

# --- 5. SUMMARY ---
echo "============================================="
echo "Services Started in tmux session '$SESSION_NAME'"
echo "---------------------------------------------"
echo "1. Jupyter Lab"
echo "   - Port: $JUPYTER_PORT"
echo "   - URL : http://<HOST_IP>:$JUPYTER_PORT"
echo ""
echo "2. TensorBoard"
echo "   - Port: $TB_PORT"
echo "   - URL : http://<HOST_IP>:$TB_PORT"
echo "---------------------------------------------"
if [ -n "$TRAIN_CMD" ]; then
    echo "3. Training"
    echo "   - Cmd : $TRAIN_CMD"
    echo "---------------------------------------------"
fi
echo "To access:"
echo "   tmux attach -t $SESSION_NAME"
echo "============================================="
