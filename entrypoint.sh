#!/usr/bin/env bash
set -euo pipefail

MAMBA_ROOT_PREFIX=/opt/conda
NOTEBOOKS_WORKSPACE_BASE="/notebooks/workspace"
STORAGE_SYSTEM_BASE="/storage/system"
FILEBROWSER_SYSTEM_BASE="${STORAGE_SYSTEM_BASE}/filebrowser"
COMFYUI_SYSTEM_BASE="${STORAGE_SYSTEM_BASE}/comfyui"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
mkdir -p "${FILEBROWSER_SYSTEM_BASE}" "${NOTEBOOKS_WORKSPACE_BASE}/input" "${NOTEBOOKS_WORKSPACE_BASE}/output" "${COMFYUI_SYSTEM_BASE}/user"

# Optionally update ComfyUI repo to the latest on container start
# Set COMFYUI_AUTO_UPDATE=0 to disable
update_comfyui() {
  local auto="${COMFYUI_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then
    return 0
  fi
  if [ ! -d "${COMFYUI_APP_BASE}/.git" ]; then
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "WARN: git not available; skipping ComfyUI update" >&2
    return 0
  fi
  echo "Updating ComfyUI in ${COMFYUI_APP_BASE} ..."
  cd "${COMFYUI_APP_BASE}"
  git pull --ff-only origin master
  micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt
}

update_comfyui

link_dir() {
  local src="$1"; local dst="$2";
  if [ -L "$src" ]; then return 0; fi
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "Migrating existing data from $src to $dst ..."
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    rm -rf "$src"
  fi
  ln -sfn "$dst" "$src"
}

link_dir "${COMFYUI_APP_BASE}/input" "${NOTEBOOKS_WORKSPACE_BASE}/input"
link_dir "${COMFYUI_APP_BASE}/output" "${NOTEBOOKS_WORKSPACE_BASE}/output"
link_dir "${COMFYUI_APP_BASE}/user" "${COMFYUI_SYSTEM_BASE}/user"

FB_DB="${FILEBROWSER_SYSTEM_BASE}/filebrowser.db"
if [ ! -f "$FB_DB" ]; then
  # Initialize database on first run
  filebrowser -d "$FB_DB" config init
fi
# Enforce noauth every startup
filebrowser -d "$FB_DB" config set --auth.method noauth

echo "Starting ComfyUI service..."
cd "${COMFYUI_APP_BASE}"
nohup python main.py --listen 127.0.0.1 --port 8189 > /tmp/comfyui.log 2>&1 &
COMFYUI_PID=$!
echo "ComfyUI started with PID: $COMFYUI_PID (port 8189)"

# Start Filebrowser service in background
echo "Starting Filebrowser service..."
nohup filebrowser --address 127.0.0.1 --port 8766 --root "${NOTEBOOKS_WORKSPACE_BASE}" --database "${FB_DB}" --baseurl /filebrowser > /tmp/filebrowser.log 2>&1 &
FILEBROWSER_PID=$!
echo "Filebrowser started with PID: $FILEBROWSER_PID (port 8766)"

# Start Studio service in background
echo "Starting Studio service..."
nohup studio --port 8765 --base-url /studio > /tmp/studio.log 2>&1 &
STUDIO_PID=$!
echo "Studio started with PID: $STUDIO_PID (port 8765)"

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi
