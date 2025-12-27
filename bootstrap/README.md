# Vast.ai Automation Bootstrap

## TL;DR: Quick Reference

**1. Vast.ai UI "On-start script"** (Copy & Edit vars):
```bash
export DATA_URL="https://drive.google.com/uc?export=download&id=1QbywOSchU-kiVut1h5tOBbEbngWljWO4"
export AUTO_START=1
export REPO_DIR="repo"

mkdir -p ~/work && cd ~/work
if [ -d "$REPO_DIR" ]; then
  cd "$REPO_DIR" && git fetch && git checkout ${BRANCH:-main} && git pull
else
  git clone -b ${BRANCH:-main} https://github.com/your-username/repo.git "$REPO_DIR"
  cd "$REPO_DIR"
fi
bash bootstrap/bootstrap.sh
```

**2. Local CLI (One-Click)**
```bash
./vast_utils/vast_up.sh ssh://root@<IP>:<PORT>
```

---

## 1. Directory Structure

Copy the `bootstrap/` and `vast_utils/` directories into the root of your project repository.

```
~/ (Home Directory)
├── work/
│   └── <repo_name>/          # This Git Repository
│       ├── .venv/            # Local venv (managed by uv)
│       ├── bootstrap/        # STARTUP SCRIPTS (Copy these to your repo)
│       └── ...
│
├── datasets/                 # SYMLINK -> /mnt/persist/datasets
├── checkpoints/              # SYMLINK -> /mnt/persist/checkpoints
└── .cache/
    ├── uv/                   # SYMLINK -> /mnt/persist/cache/uv
    ├── pip/                  # SYMLINK -> /mnt/persist/cache/pip
    ├── huggingface/          # SYMLINK -> /mnt/persist/cache/huggingface
    └── torch/                # SYMLINK -> /mnt/persist/cache/torch
```

## 2. Quick Start

### A. Vast.ai UI (On-Start Script)

Paste this into the **"On-start script"** field in the Vast.ai template configuration.  
Replace `YOUR_REPO_URL` and `DATA_URL`.

```bash
# Vast.ai Startup One-Liner
export DATA_URL="https://drive.google.com/uc?export=download&id=1QbywOSchU-kiVut1h5tOBbEbngWljWO4"
export AUTO_START=1
# Optional: export BRANCH="feature/foo"
export REPO_DIR="repo"

mkdir -p ~/work
cd ~/work
# Idempotent Clone/Update
if [ -d "$REPO_DIR" ]; then
  cd "$REPO_DIR" && git fetch && git checkout ${BRANCH:-main} && git pull
else
  git clone -b ${BRANCH:-main} https://github.com/your-username/repo.git "$REPO_DIR"
  cd "$REPO_DIR"
fi
# Run Bootstrap
bash bootstrap/bootstrap.sh
```

### B. Local CLI (One-Click)

Use the `vast_utils/vast_up.sh` helper script from your local machine to setup a remote instance:

```bash
# 1. Define your env (or hardcode in script)
export REPO_URL="https://github.com/your-username/repo.git"
export DATA_URL="https://your-server.com/datasets/NYUv2.tar.zst"

# 2. Run against the Vast instance
# usage: ./vast_up.sh ssh://root@<ip>:<port>
./vast_utils/vast_up.sh ssh://root@1.2.3.4:10022
```

### C. Manual Setup (Existing Instance)

If you are already logged into the instance via SSH:

```bash
# 1. Export Config
export DATA_URL="https://your-server.com/datasets/NYUv2.tar.zst"
export AUTO_START=1

# 2. Setup Repo
mkdir -p ~/work && cd ~/work
git clone https://github.com/your-username/repo.git
cd repo

# 3. Bootstrap
bash bootstrap/bootstrap.sh
```

---

## 3. Configuration (Environment Variables)

Set these in the Vast.ai "Docker Options" (-e VAR=val) or in the startup script.
These control the behavior of `bootstrap.sh` and `start_services.sh`.

### Core
| Variable | Default | Description |
| :--- | :--- | :--- |
| `DATA_URL` | *(Required)* | URL to a `tar.zst` dataset file. |
| `DATASET_NAME`| `NYUv2` | Name of folder in `~/datasets/`. |
| `BRANCH` | `main` | Git branch to checkout (used by vast_up/UI script). |
| `REPO_DIR` | `repo` | Local directory name for the cloned repo. |

### Service Automation
| Variable | Default | Description |
| :--- | :--- | :--- |
| `AUTO_START` | `0` | Set to `1` to launch tmux services automatically. |
| `RESTART_SERVICES` | `0` | Set to `1` to force kill/restart existing tmux session. |
| `JUPYTER_PORT` | `8888` | Port for Jupyter Lab. |
| `TENSORBOARD_PORT`| `6006` | Port for TensorBoard. |

### Commands (Advanced)
**⚠️ WARNING:** Do NOT include newlines or EOF markers in these variables. They are written to runner scripts and will break execution if malformed.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `JUPYTER_CMD` | `jupyter lab ...` | Command to start Jupyter. |
| `TENSORBOARD_CMD` | `tensorboard ...` | Command to start TensorBoard. |
| `TRAIN_CMD` | *(Empty)* | If set, a training window will open and this runs. |

## 4. Troubleshooting & Operations

### Logs
- **Setup Logs**: `~/bootstrap.log` (Contains all bootstrap output)
- **Service Logs**: `~/logs/` (jupyter.log, tensorboard.log, train.log)

### Common Actions
- **Check Status**: `bash bootstrap/healthcheck.sh`
- **Attach to Session**: `tmux attach -t main`
- **Stop Services**: `tmux kill-session -t main`
- **Update Repo**: `git pull` then `bash bootstrap/bootstrap.sh` (Idempotent: usually safe to re-run)

### Accessing Services (SSH Tunneling)
If Vast.ai ports are not exposed publicly, use SSH tunneling to access Jupyter/TensorBoard securely:

```bash
# Local machine
# Forward 8888 (Jupyter) and 6006 (TensorBoard)
ssh -L 8888:localhost:8888 -L 6006:localhost:6006 -p <ssh_port> root@<ssh_ip>
```
Then access via `http://localhost:8888` and `http://localhost:6006`.

### Manual Verification (Smoke Test)
Run these commands on the instance to verify correct setup:

1. **Persistence Check**:
    ```bash
    mountpoint -q /mnt/persist && echo "OK: Persist Mounted" || echo "WARN: Not Mounted (Ephemeral)"
    ```
2. **Port Listen Check** (after start_services):
    ```bash
    ss -ltn | egrep ':(8888|6006)'
    # Should show LISTENING lines for both ports
    ```

### Persistence
- The system tries to mount `/mnt/persist`.
- If missing, it falls back to a local (`mkdir -p /mnt/persist`) to allow scripts to run.
- **WARNING**: If `mountpoint /mnt/persist` returns false, data stored here is **ephemeral** and will be lost when the instance is destroyed.
