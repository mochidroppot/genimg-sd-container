# ----------------------------------------------------------------------------
# Image for Paperspace Notebook (GPU) running JupyterLab + ComfyUI + TensorBoard
# - Base: NVIDIA CUDA 12.4 runtime (Ubuntu 22.04) with cuDNN
# - Package manager: micromamba (conda-compatible)
# - Default: launches JupyterLab on port 8888 and TensorBoard on port 6006
# ----------------------------------------------------------------------------
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# ------------------------------
# Build-time and runtime settings
# ------------------------------
ARG PYTHON_VERSION=3.11
ARG MAMBA_USER=mambauser
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    SHELL=/bin/bash \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ------------------------------
# Tini (PID 1 init) for stable process handling inside containers
# ------------------------------
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini

# ------------------------------
# Base packages
# - bzip2: extract micromamba tarball
# - libgl1/libglib2.0-0: common GUI/ML deps
# - iproute2: provides `ss` used in HEALTHCHECK
# ------------------------------
RUN set -eux; \
    chmod +x /tini && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git nano vim tzdata build-essential \
      libgl1 libglib2.0-0 openssh-client bzip2 pkg-config iproute2 && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------
# micromamba (system-wide)
# ------------------------------
ENV MAMBA_ROOT_PREFIX=/opt/conda
# Retrieve micromamba and install to /usr/local/bin; fall back to install.sh if layout changes
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

# ------------------------------
# Python environment (isolated prefix)
# ------------------------------
RUN set -eux; \
    micromamba create -y -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python=${PYTHON_VERSION}; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python -m pip install --upgrade pip && \
    micromamba clean -a -y

# All following conda/pip operations should use micromamba run -p
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}

# ------------------------------
# Core Python libraries for Notebook workflows
# ------------------------------
RUN set -eux; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git jupyter-server-proxy tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich && \
    micromamba clean -a -y

# ------------------------------
# Application: ComfyUI
# ------------------------------
RUN set -eux; \
    mkdir -p /opt/app && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI

# PyTorch (CUDA 12.4 wheels) + ComfyUI requirements
RUN set -eux; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt && \
    micromamba clean -a -y

# ------------------------------
# Non-root user for interactive sessions
# ------------------------------
RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} ${MAMBA_ROOT_PREFIX}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /opt/app

# Workspace directories for notebooks and data
RUN mkdir -p /workspace /workspace/data /workspace/notebooks
WORKDIR /workspace

# Switch to non-root; set Python env in PATH
USER ${MAMBA_USER}
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

# ------------------------------
# Healthcheck (Jupyter 8888 / TensorBoard 6006)
# ------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc 'ss -ltn | grep -E ":8888|:6006|:8188" >/dev/null || exit 1'

# ------------------------------
# Entrypoint via Tini
# ------------------------------
USER root
WORKDIR /workspace

# Cache directories (Paperspace persistent volume typically mounted at /storage)
ENV TENSORBOARD_LOGDIR=/storage/runs \
    HF_HOME=/storage/.cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/storage/.cache/huggingface \
    TRANSFORMERS_CACHE=/storage/.cache/huggingface \
    PIP_CACHE_DIR=/storage/.cache/pip \
    COMFYUI_PORT=8188

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chown ${MAMBA_USER}:${MAMBA_USER} /usr/local/bin/entrypoint.sh

# Expose Jupyter and TensorBoard port. (ComfyUI proxied at /proxy/8188/)
EXPOSE 8888 6006

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint.sh"]
USER ${MAMBA_USER}

# Default command (JupyterLab)
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password="]
