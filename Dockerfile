# ベース: NVIDIA 公式 CUDA + cuDNN (Ubuntu 22.04)
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# 非対話設定と基本ツール
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    SHELL=/bin/bash \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # NVIDIA ランタイム向け
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Tini: プロセス管理（Jupyter 等の安定化に必須）
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN set -eux; \
    chmod +x /tini && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git nano vim tzdata build-essential \
      libgl1 libglib2.0-0 openssh-client && \
    rm -rf /var/lib/apt/lists/*

# micromamba で Python 環境を構築
ARG MAMBA_USER=mambauser
ARG PYTHON_VERSION=3.11
ENV MAMBA_ROOT_PREFIX=/opt/conda
SHELL ["/bin/bash", "-lc"]

# 非 root ユーザー（Paperspace 実行時の権限分離・ファイルパーミッション安定化）
RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER} && \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER}
USER ${MAMBA_USER}

# micromamba インストール
WORKDIR /home/${MAMBA_USER}
ADD https://micro.mamba.pm/api/micromamba/linux-64/latest micromamba.tar.bz2
RUN set -eux; \
    mkdir -p ${MAMBA_ROOT_PREFIX}; \
    tar -xjf micromamba.tar.bz2 -C /tmp && \
    /tmp/bin/micromamba shell init -s bash -p ${MAMBA_ROOT_PREFIX} && \
    echo 'export PATH="${MAMBA_ROOT_PREFIX}/bin:${PATH}"' >> ~/.bashrc && \
    source ~/.bashrc && \
    micromamba create -y -n pyenv python=${PYTHON_VERSION} && \
    micromamba clean -a -y
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

WORKDIR /opt/app
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Python ライブラリ
RUN pip install --upgrade pip && \
    pip install \
      jupyterlab==4.* \
      notebook \
      ipywidgets \
      jupyterlab-git \
      tensorboard \
      matplotlib seaborn pandas numpy scipy \
      tqdm rich && \
    pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision && \
    pip install -r /opt/app/ComfyUI/requirements.txt && \
    pip cache purge

# ノートブック/データ用の作業ディレクトリ
RUN mkdir -p /workspace && mkdir -p /workspace/data && mkdir -p /workspace/notebooks
WORKDIR /workspace

# ポート公開（Jupyter/TensorBoard）
EXPOSE 8888 6006

# ヘルスチェック（Jupyter が立ち上がっているか簡易確認）
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc 'ss -ltn | grep -E ":8888|:6006" >/dev/null || exit 1'

# Entrypoint: Tini 経由で安定実行
USER root
ENTRYPOINT ["/tini", "--"]
USER ${MAMBA_USER}

# デフォルト起動（JupyterLab）
CMD ["bash", "-lc", "jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' --allow-root"]
