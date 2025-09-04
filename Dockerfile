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

USER ${MAMBA_USER}
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

# ノートブック/データ用の作業ディレクトリ
RUN mkdir -p /workspace /workspace/data /workspace/notebooks
WORKDIR /workspace

# ポート公開（Jupyter/TensorBoard）
EXPOSE 8888 6006

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc 'ss -ltn | grep -E ":8888|:6006" >/dev/null || exit 1'

# Entrypoint: Tini 経由
USER root
ENTRYPOINT ["/tini", "--"]
USER ${MAMBA_USER}

# デフォルト起動（JupyterLab）
CMD ["bash", "-lc", "jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' --allow-root"]
