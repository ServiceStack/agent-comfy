FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive PIP_PREFER_BINARY=1

RUN apt-get update && apt-get install -y git wget jq curl ffmpeg && apt-get clean
ENV ROOT=/stable-diffusion
ENV DATA=/data
RUN mkdir -p ${DATA}/custom_nodes

RUN ln -sT /data/.cache /root/.cache

# Clone and setup ComfyUI-Florence2
RUN echo "Downloading image captioning support module..." && \
    cd ${DATA}/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-Florence2.git ${DATA}/custom_nodes/ComfyUI-Florence2 && \
    cd ${DATA}/custom_nodes/ComfyUI-Florence2 && \
    git reset --hard 375b92e5f6c0e07922b87cd68561c10f69ed257e && \
    pip install -r requirements.txt && \
    pip install accelerate==0.31.0

# Clone and setup ComfyUI-Custom-Scripts
RUN echo "Downloading text utils for image captioning..." && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git ${DATA}/custom_nodes/ComfyUI-Custom-Scripts && \
    cd ${DATA}/custom_nodes/ComfyUI-Custom-Scripts && \
    git reset --hard b0f21a3c13bac21068d1dcceb7c2d466167054b3

RUN echo "Downloading text to speech support extension..." && \
    git clone https://github.com/yuvraj108c/ComfyUI-PiperTTS.git ${DATA}/custom_nodes/ComfyUI-PiperTTS && \
    cd ${DATA}/custom_nodes/ComfyUI-PiperTTS && \
    git reset --hard fb7e1ce91f08b66e623a2605f528790086162645 && \
    pip install -r requirements.txt

# Clone and setup ComfyUI
RUN --mount=type=cache,target=/root/.cache/pip \
  git clone --depth 1 --branch v0.2.4 https://github.com/comfyanonymous/ComfyUI.git ${ROOT} && \
  cd ${ROOT} && \
  pip install -r requirements.txt && \
  rm -rf ${ROOT}/input ${ROOT}/output ${ROOT}/custom_nodes ${ROOT}/models

# Fix for binding port issue
RUN pip install yarl==1.12.1

# Create symlinks
RUN ln -sT /data/input ${ROOT}/input && \
    ln -sT /data/custom_nodes ${ROOT}/custom_nodes && \
    ln -sT /data/models ${ROOT}/models

WORKDIR ${ROOT}
COPY . /docker/
COPY ./ai-agent-extension ${DATA}/custom_nodes/ai-agent-extension
RUN pip install -r ${DATA}/custom_nodes/ai-agent-extension/requirements.txt
RUN chmod u+x /docker/init_models.sh
RUN chmod u+x /docker/entrypoint.sh && cp /docker/extra_model_paths.yaml ${ROOT}
# Create directories
RUN mkdir -p /data/.cache /data/input /data/output /data/custom_nodes /data/models \
    /data/embeddings /data/models/Stable-diffusion /data/models/LDSR \
    /data/models/VAE /data/models/checkpoints /data/models/clip



WORKDIR ${ROOT}

ENV NVIDIA_VISIBLE_DEVICES=all PYTHONPATH="${PYTHONPATH}:${PWD}" CLI_ARGS=""
EXPOSE 7860
ENTRYPOINT ["/docker/entrypoint.sh"]
CMD python -u main.py --listen --port 7860 ${CLI_ARGS}
