#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_BASE="/storage/workspace"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
mkdir -p "/storage/system/filebrowser" "${WORKSPACE_BASE}/input" "${WORKSPACE_BASE}/output"

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

link_dir "${COMFYUI_APP_BASE}/input" "${WORKSPACE_BASE}/input"
link_dir "${COMFYUI_APP_BASE}/output" "${WORKSPACE_BASE}/output"

FB_DB="/storage/system/filebrowser/filebrowser.db"
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
