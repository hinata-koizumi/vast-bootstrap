#!/bin/bash
set -e

# --- SETUP ---
TEST_ROOT="$(pwd)/tests/run_$(date +%s)"
MOCK_HOME="$TEST_ROOT/home"
MOCK_PERSIST="$TEST_ROOT/persist"
BOOTSTRAP_DIR="$(pwd)/bootstrap"

mkdir -p "$MOCK_HOME" "$MOCK_PERSIST"
# Create dummy repo dir as it would be on valid run
mkdir -p "$MOCK_HOME/work/repo/.venv/bin"
touch "$MOCK_HOME/work/repo/.venv/bin/activate"

# MOCK tmux
tmux() {
    echo "[MOCK_TMUX] $*" >> "$TEST_ROOT/tmux.log"
    if [ "$1" == "has-session" ]; then return 1; fi # Always say session not found
    return 0
}
export -f tmux

# Create Dummy Data
DATA_FILE="$TEST_ROOT/dummy_data.tar.zst"
mkdir -p "$TEST_ROOT/data_src/NYUv2"
echo "Dummy Data Content" > "$TEST_ROOT/data_src/NYUv2/README.md"
# Create tar.zst
tar -C "$TEST_ROOT/data_src" -c NYUv2 | zstd > "$DATA_FILE"

echo "=== STARTING SMOKE TEST ==="
echo "Test Root: $TEST_ROOT"

# --- 1. MOUNTS TEST ---
echo "[Test] Mounts..."
# Override HOME and PERSIST_ROOT
export HOME="$MOCK_HOME"
export PERSIST_ROOT="$MOCK_PERSIST"

# Run mounts.sh
bash "$BOOTSTRAP_DIR/mounts.sh"

# Verify Symlinks
if [ -L "$MOCK_HOME/datasets" ] && [ "$(readlink "$MOCK_HOME/datasets")" == "$MOCK_PERSIST/datasets" ]; then
    echo "  [PASS] ~/datasets linked correctly."
else
    echo "  [FAIL] ~/datasets link broken."
    exit 1
fi
if [ -d "$MOCK_PERSIST/cache/uv" ]; then
    echo "  [PASS] persist cache dirs created."
else
    echo "  [FAIL] persist cache dirs missing."
    exit 1
fi

# --- 2. DATA SYNC TEST ---
echo "[Test] Data Sync..."
export DATA_URL="file://$DATA_FILE"
export DATASET_NAME="NYUv2" # Match what we tarred

# Run data_sync (First Run)
bash "$BOOTSTRAP_DIR/data_sync.sh"

# Verify content
if [ -f "$MOCK_HOME/datasets/NYUv2/README.md" ]; then
    echo "  [PASS] Data extracted."
else
    echo "  [FAIL] Data extraction failed."
    exit 1
fi

# Verify Sentinel
if [ -f "$MOCK_HOME/datasets/NYUv2/.complete" ]; then
    echo "  [PASS] Sentinel created."
else
    echo "  [FAIL] Sentinel missing."
    exit 1
fi

# Run data_sync (Second Run - Idempotency)
echo "[Test] Data Sync (Idempotency)..."
START_TIME=$(date +%s)
bash "$BOOTSTRAP_DIR/data_sync.sh"
END_TIME=$(date +%s)
# Should be instantaneous (checking sentinel)
if [ "$((END_TIME - START_TIME))" -le 2 ]; then
    echo "  [PASS] Idempotent run was fast."
else
    echo "  [WARN] Idempotent run took > 2s ($((END_TIME - START_TIME))s)."
fi

# --- 3. SERVICES TEST ---
echo "[Test] Services..."
export AUTO_START=1
export REPO_ROOT="$MOCK_HOME/work/repo"
# Need to copy bootstrap to repo location as start_services expects to run relative to it?
# start_services.sh uses SCRIPT_DIR to find REPO_ROOT. 
# If we run it from current location, SCRIPT_DIR is .../vast_bootstrap/bootstrap
# REPO_ROOT becomes .../vast_bootstrap
# But we mocked the venv at $MOCK_HOME/work/repo/.venv
# This mismatch causes venv check failure.
# FIX: Symlink our bootstrap dir into the mock repo
mkdir -p "$MOCK_HOME/work/repo/bootstrap"
cp "$BOOTSTRAP_DIR/"* "$MOCK_HOME/work/repo/bootstrap/"

# Now run start_services.sh from the mock repo
(
    cd "$MOCK_HOME/work/repo"
    # We need to export HOME again inside subshell or just rely on inherited
    bash bootstrap/start_services.sh
)

# Verify tmux calls
if grep -q "new-session -d -s main" "$TEST_ROOT/tmux.log"; then
    echo "  [PASS] tmux new-session called."
else
    echo "  [FAIL] tmux new-session NOT called."
    cat "$TEST_ROOT/tmux.log"
    exit 1
fi
if grep -q "Starting Command" "$TEST_ROOT/tmux.log" 2>/dev/null; then
    # runner script content won't appear in tmux log because we write to file
    # but "send-keys ... bash ...runner...sh" should appear
    :
fi
# Check if runner script keys observe
if grep -q "runner_script" "$TEST_ROOT/tmux.log"; then
     echo "  [FAIL] Found raw variable name 'runner_script' in log? (Check expansion)"
fi
# Check if valid send-keys
if grep -q "send-keys.*bash.*run_" "$TEST_ROOT/tmux.log"; then
    echo "  [PASS] Runner script execution sent to tmux."
else
    echo "  [FAIL] Runner script not triggered."
    cat "$TEST_ROOT/tmux.log"
    exit 1
fi

echo "=== ALL TESTS PASSED ==="
