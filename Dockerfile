# ----------------------------------------------------------------------------
# Image for Paperspace Notebook (GPU) running JupyterLab
# - Base: NVIDIA CUDA 12.4 runtime (Ubuntu 22.04) with cuDNN
# - Package manager: micromamba (conda-compatible)
# - Default: launches JupyterLab on port 8888
# ----------------------------------------------------------------------------
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

LABEL maintainer="mochidroppot <mochidroppot@gmail.com>"

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
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    MAMBA_ROOT_PREFIX=/opt/conda

# ------------------------------
# Base packages
# - bzip2: extract micromamba tarball
# - libgl1/libglib2.0-0: common GUI/ML deps
# - iproute2: provides `ss` used in HEALTHCHECK
# ------------------------------
RUN set -eux; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    { \
      echo "deb https://archive.ubuntu.com/ubuntu ${codename} main universe multiverse restricted"; \
      echo "deb https://archive.ubuntu.com/ubuntu ${codename}-updates main universe multiverse restricted"; \
      echo "deb https://security.ubuntu.com/ubuntu ${codename}-security main universe multiverse restricted"; \
    } > /etc/apt/sources.list; \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" install -y --no-install-recommends \
      ca-certificates curl wget git nano vim zip unzip tzdata build-essential \
      libgl1-mesa-glx libglib2.0-0 openssh-client bzip2 pkg-config iproute2 tini ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------
# micromamba (system-wide)
# ------------------------------
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

ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}

# ------------------------------
# Application: ComfyUI
# ------------------------------
RUN set -eux; \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI && \
    mkdir -p /opt/app/ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git clone https://github.com/mit-han-lab/ComfyUI-nunchaku /opt/app/ComfyUI/custom_nodes/nunchaku_nodes && \
    git config --global --add safe.directory /opt/app/ComfyUI

# PyTorch (CUDA 12.4 wheels) + Core libs + ComfyUI requirements
RUN set -eux; \
    export PIP_NO_CACHE_DIR=0; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision torchaudio && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --prefer-binary --upgrade-strategy only-if-needed \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git jupyter-server-proxy tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich && \
    if [ -f /opt/app/ComfyUI/requirements.txt ]; then \
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt; \
    fi; \
    if [ -f /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python -m pip install https://github.com/nunchaku-tech/nunchaku/releases/download/v0.3.1/nunchaku-0.3.1+torch2.7-cp311-cp311-linux_x86_64.whl; \
    micromamba clean -a -y

# ------------------------------
# Filebrowser
# ------------------------------
RUN set -eux; \
    mkdir -p /tmp/fb && \
    curl -fsSL -o /tmp/fb/linux-amd64-filebrowser.tar.gz "https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz" && \
    tar -xzf /tmp/fb/linux-amd64-filebrowser.tar.gz -C /tmp/fb && \
    install -m 0755 /tmp/fb/filebrowser /usr/local/bin/filebrowser && \
    rm -rf /tmp/fb

# ------------------------------
# studio
# ------------------------------
  RUN set -eux; \
  mkdir -p /tmp/studio && \
  curl -fsSL -o /tmp/studio/studio.zip "https://github.com/mochidroppot/paperspace-stable-diffusion-station/releases/latest/download/paperspace-stable-diffusion-station-linux-amd64.zip" && \
  unzip /tmp/studio/studio.zip -d /tmp/studio && \
  install -m 0755 /tmp/studio/studio/studio /usr/local/bin/studio && \
  rm -rf /tmp/studio

# ------------------------------
# Non-root user for interactive sessions
# ------------------------------
RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} ${MAMBA_ROOT_PREFIX}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /opt/app

# Configure git for the mambauser
USER ${MAMBA_USER}
RUN git config --global --add safe.directory /opt/app/ComfyUI

# Switch back to root for workspace setup
USER root

# Workspace directories for notebooks and data
RUN mkdir -p /workspace /workspace/data /workspace/notebooks
WORKDIR /workspace

# Switch to non-root; set Python env in PATH
USER ${MAMBA_USER}
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

# ------------------------------
# Healthcheck (Jupyter 8888)
# ------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc 'ss -ltn | grep -E ":8888" >/dev/null || exit 1'

# ------------------------------
# Entrypoint via Tini
# ------------------------------
USER root
WORKDIR /notebook

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chown ${MAMBA_USER}:${MAMBA_USER} /usr/local/bin/entrypoint.sh


# Install ComfyUI ProxyFix extension as a custom node (single copy)
COPY ComfyUI-ProxyFix /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix

# Install local jupyter-server-proxy entrypoints package
COPY pyproject.toml /tmp/paperspace-stable-diffusion-suite/pyproject.toml
COPY src /tmp/paperspace-stable-diffusion-suite/src
RUN micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /tmp/paperspace-stable-diffusion-suite && rm -rf /tmp/paperspace-stable-diffusion-suite

# Expose Jupyter port.
EXPOSE 8888

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
USER ${MAMBA_USER}

# Default command (JupyterLab)
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password="]
