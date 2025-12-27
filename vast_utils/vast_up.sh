#!/bin/bash
set -e

# === Configuration ===
# You can hardcode this or pass it as an arg/env
REPO_URL="${REPO_URL:-https://github.com/your-username/your-repo.git}"
BRANCH="${BRANCH:-main}"

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <instance_id> [ssh_port] [ssh_user]"
    echo "   OR: $0 ssh://root@<ip>:<port>"
    echo ""
    echo "Examples:"
    echo "  $0 12345            (Assumes 'vastai ssh-url' output format or mapping)"
    echo "  $0 root@1.2.3.4 -p 12345"
    echo "  $0 ssh://root@1.2.3.4:12345"
    exit 1
fi

# Parsing logic (Simplified for "ssh connection string" or "host port")
# User said: "vast create -> ssh -> bootstrap" simplified.
# If the user provides the full SSH command or URI, we parse it.
# Let's assume the user passes the standard SSH destination string: "root@1.2.3.4" and port "-p XXXXX" 
# OR just the raw args they would pass to ssh.
# To make it "one click", we usually wrap the whole command.

echo "=== [vast_up.sh] Deploying to Remote ==="

SSH_ARGS=("$@")

# Remote Script to execute
# 1. Setup ~/.ssh if needed (github keys) - skipped, assumed agent forwarding or public repo
# 2. Clone/Update Repo
# 3. Run Bootstrap

REMOTE_CMD="
set -e
echo '>>> Connected to instance.'

# 1. Setup Work Directory
mkdir -p ~/work
cd ~/work

# 2. Clone or Pull
dirname=\$(basename $REPO_URL .git)
if [ -d \"\$dirname\" ]; then
    echo \">>> Updating existing repo...\"
    cd \"\$dirname\"
    git fetch
    git checkout $BRANCH
    git pull
else
    echo \">>> Cloning setup...\"
    git clone -b $BRANCH $REPO_URL
    cd \"\$dirname\"
fi

# 3. Run Bootstrap
echo \">>> Running Bootstrap...\"
# Pass necessary env vars if needed. For now bootstrap.sh asks for ENV vars.
# We can inject them here if local env has them.
export DATASET_NAME=\"\${DATASET_NAME}\"
export DATA_URL=\"\${DATA_URL}\"
export AUTO_START=\"\${AUTO_START:-0}\"

bash bootstrap/bootstrap.sh
"

echo "Running install on remote..."
# use -A for agent forwarding if using private repo
ssh -A -o StrictHostKeyChecking=no "${SSH_ARGS[@]}" "$REMOTE_CMD"

echo "=== [vast_up.sh] Done. ==="
