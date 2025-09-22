#!/usr/bin/env bash
set -euo pipefail

NOTEBOOKS_WORKSPACE_BASE="/notebooks/workspace"
STORAGE_SYSTEM_BASE="/storage/system"
FILEBROWSER_SYSTEM_BASE="${STORAGE_SYSTEM_BASE}/filebrowser"
COMFYUI_SYSTEM_BASE="${STORAGE_SYSTEM_BASE}/comfyui"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
mkdir -p "${FILEBROWSER_SYSTEM_BASE}" "${NOTEBOOKS_WORKSPACE_BASE}/input" "${NOTEBOOKS_WORKSPACE_BASE}/output" "${COMFYUI_SYSTEM_BASE}/user"

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

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi
