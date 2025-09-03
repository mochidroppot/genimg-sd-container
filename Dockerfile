FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
RUN pip install --upgrade pip && \
    pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision && \
    pip install -r /opt/app/ComfyUI/requirements.txt

EXPOSE 8188 6006
CMD ["bash", "-lc", "python /opt/app/ComfyUI/main.py --listen 0.0.0.0 --port 8188"]
