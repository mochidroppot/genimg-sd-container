# ベース: NVIDIA 公式 CUDA + cuDNN (Ubuntu 22.04) - CUDA 12.1
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    SHELL=/bin/bash \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Tini: プロセス管理（Jupyter 等の安定化に有用）
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini

# 基本ツール（micromamba 展開に bzip2 必須）
RUN set -eux; \
    chmod +x /tini && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git nano vim tzdata build-essential \
      libgl1 libglib2.0-0 openssh-client bzip2 pkg-config && \
    rm -rf /var/lib/apt/lists/*

# micromamba を root でインストール（/usr/local/bin へ配置）
ARG PYTHON_VERSION=3.11
ENV MAMBA_ROOT_PREFIX=/opt/conda
ADD https://micro.mamba.pm/api/micromamba/linux-64/latest micromamba.tar.bz2

# micromamba の取得とセットアップ（壊れたキャッシュ対策つき）
RUN set -eux; \
    mkdir -p ${MAMBA_ROOT_PREFIX}; \
    curl -fsSL -o /tmp/micromamba.tar.bz2 "https://micro.mamba.pm/api/micromamba/linux-64/latest"; \
    if tar -tjf /tmp/micromamba.tar.bz2 | grep -q '^bin/micromamba$'; then \
      tar -xjf /tmp/micromamba.tar.bz2 -C /usr/local/bin --strip-components=1 bin/micromamba; \
    else \
      echo "micromamba tar layout unexpected; falling back to install.sh"; \
      curl -fsSL -o /tmp/install_micromamba.sh https://micro.mamba.pm/install.sh; \
      bash /tmp/install_micromamba.sh -b -p ${MAMBA_ROOT_PREFIX}; \
      ln -sf ${MAMBA_ROOT_PREFIX}/bin/micromamba /usr/local/bin/micromamba; \
    fi; \
    micromamba --version; \
    echo "export PATH=${MAMBA_ROOT_PREFIX}/bin:\$PATH" > /etc/profile.d/mamba.sh

# Python 環境の作成（絶対パス指定で安全に）
RUN set -eux; \
    micromamba create -y -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python=${PYTHON_VERSION}; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python -m pip install --upgrade pip && \
    micromamba clean -a -y

# 以降の pip/conda 操作は micromamba run -p で実行
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}

# Python ライブラリ（Jupyter/TensorBoard 等）
RUN set -eux; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich && \
    micromamba clean -a -y

# アプリ用ディレクトリと ComfyUI の取得
RUN set -eux; \
    mkdir -p /opt/app && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI

# PyTorch（CUDA 12.1 と整合する cu121 ホイールを使用）
RUN set -eux; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --index-url https://download.pytorch.org/whl/cu121 torch torchvision && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt && \
    micromamba clean -a -y

# 非 root ユーザー作成（最後に所有権を調整）
ARG MAMBA_USER=mambauser
RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} ${MAMBA_ROOT_PREFIX}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /opt/app

# ノートブック/データ用の作業ディレクトリ
RUN mkdir -p /workspace /workspace/data /workspace/notebooks
WORKDIR /workspace

USER ${MAMBA_USER}
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc 'ss -ltn | grep -E ":8888|:6006" >/dev/null || exit 1'

# Entrypoint: Tini 経由
USER root
WORKDIR /workspace

ENV TENSORBOARD_LOGDIR=/storage/runs \
    HF_HOME=/storage/.cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/storage/.cache/huggingface \
    TRANSFORMERS_CACHE=/storage/.cache/huggingface \
    PIP_CACHE_DIR=/storage/.cache/pip

# 起動用 ENTRYPOINT スクリプトを用意（TB を起動し、渡されたコマンドを実行）
RUN printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  '# 1) ComfyUI 永続ディレクトリのセットアップ' \
  'PERSIST_BASE="/storage/comfyui"' \
  'APP_BASE="/opt/app/ComfyUI"' \
  'mkdir -p "${PERSIST_BASE}/models" "${PERSIST_BASE}/custom_nodes" "${PERSIST_BASE}/input" "${PERSIST_BASE}/output"' \
  '' \
  'link_dir() {' \
  '  local src="$1"; local dst="$2";' \
  '  # 既にシンボリックリンクならそのまま' \
  '  if [ -L "$src" ]; then return 0; fi' \
  '  # 既存ディレクトリに内容があれば永続側へ移行（初回のみ）' \
  '  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then' \
  '    echo "Migrating existing data from $src to $dst ..."' \
  '    mkdir -p "$dst"' \
  '    cp -a "$src"/. "$dst"/' \
  '    rm -rf "$src"' \
  '  fi' \
  '  # シンボリックリンクを作成' \
  '  ln -sfn "$dst" "$src"' \
  '}' \
  '' \
  'link_dir "${APP_BASE}/models" "${PERSIST_BASE}/models"' \
  'link_dir "${APP_BASE}/custom_nodes" "${PERSIST_BASE}/custom_nodes"' \
  'link_dir "${APP_BASE}/input" "${PERSIST_BASE}/input"' \
  'link_dir "${APP_BASE}/output" "${PERSIST_BASE}/output"' \
  '' \
  '# 2) キャッシュ/ログのディレクトリも作成' \
  'mkdir -p "${TENSORBOARD_LOGDIR:-/storage/runs}" "${HF_HOME:-/storage/.cache/huggingface}" "${PIP_CACHE_DIR:-/storage/.cache/pip}"' \
  '' \
  '# 3) TensorBoard をバックグラウンド起動' \
  '(tensorboard --logdir "${TENSORBOARD_LOGDIR:-/storage/runs}" --host 0.0.0.0 --port 6006 >/tmp/tensorboard.log 2>&1 &)' \
  '' \
  '# 4) Paperspace が与えるコマンド（例: jupyter lab ...）をそのまま実行。無ければデフォルト起動' \
  'if [ "$#" -gt 0 ]; then' \
  '  exec "$@"' \
  'else' \
  '  exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=' \
  'fi' \
  > /usr/local/bin/entrypoint.sh && \
  chmod +x /usr/local/bin/entrypoint.sh && \
  chown ${MAMBA_USER}:${MAMBA_USER} /usr/local/bin/entrypoint.sh

# ポート公開（Jupyter/TensorBoard）
EXPOSE 8888 6006

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint.sh"]
USER ${MAMBA_USER}

# デフォルト起動（JupyterLab）
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password="]
