#!/usr/bin/env bash
set -euo pipefail

# 1) Setup persistent directories for work
WORKSPACE_BASE="/storage/workspace"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
mkdir -p "${WORKSPACE_BASE}/models" "${WORKSPACE_BASE}/custom_nodes" "${WORKSPACE_BASE}/input" "${WORKSPACE_BASE}/output"

link_dir() {
  local src="$1"; local dst="$2";
  # If already a symlink, nothing to do
  if [ -L "$src" ]; then return 0; fi
  # If a real dir with content exists, migrate to persistent side once
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "Migrating existing data from $src to $dst ..."
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    rm -rf "$src"
  fi
  # Create/update symlink
  ln -sfn "$dst" "$src"
}

link_dir "${COMFYUI_APP_BASE}/models" "${WORKSPACE_BASE}/models"
link_dir "${COMFYUI_APP_BASE}/custom_nodes" "${WORKSPACE_BASE}/custom_nodes"
link_dir "${COMFYUI_APP_BASE}/input" "${WORKSPACE_BASE}/input"
link_dir "${COMFYUI_APP_BASE}/output" "${WORKSPACE_BASE}/output"

# 2) Ensure cache/log directories exist
mkdir -p "${TENSORBOARD_LOGDIR:-/storage/runs}" "${HF_HOME:-/storage/.cache/huggingface}" "${PIP_CACHE_DIR:-/storage/.cache/pip}"

# 3) Start TensorBoard in the background
(tensorboard --logdir "${TENSORBOARD_LOGDIR:-/storage/runs}" --host 0.0.0.0 --port 6006 >/tmp/tensorboard.log 2>&1 &)

# 4) Start ComfyUI in the background (loopback-only; reachable via JupyterLab proxy at /proxy/${COMFYUI_PORT}/)
(cd "${COMFYUI_APP_BASE}" && python main.py --listen 127.0.0.1 --port "${COMFYUI_PORT:-8188}" >/tmp/comfyui.log 2>&1 &)

# 5) Execute given command (e.g., from Paperspace), else launch JupyterLab
if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi
