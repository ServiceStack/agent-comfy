#!/bin/bash

set -Eeuo pipefail

# Init known folders
mkdir -vp /data/embeddings \
  /data/models/Stable-diffusion \
  /data/models/LDSR \
  /data/models/VAE \
  /data/models/checkpoints \
  /data/models/clip \
  /data/output \
  /data/config

# Check if LOCAL_DEBUG is set, if not, show warning that ai-agent-extension won't be supported
# First initialize LOCAL_DEBUG
LOCAL_DEBUG=${LOCAL_DEBUG:-}
HF_TOKEN=${HF_TOKEN:-}

if [ -f /docker/init_models.sh ]; then
  echo "Running init_models.sh..."
  bash /docker/init_models.sh
fi

# Only for debug, if ai-agent-extension is mounted, make a symlink
if [ -n "$LOCAL_DEBUG" ]; then
  if [ -d /data/ai-agent-extension ]; then
    echo "LOCAL_DEBUG is set, ai-agent-extension is mounted."
    # Remove built in ai-agent-extension and make a symlink
    rm -rf /stable-diffusion/custom_nodes/ai-agent-extension
    ln -s /data/ai-agent-extension /stable-diffusion/custom_nodes/ai-agent-extension
  else
    echo "Warning: LOCAL_DEBUG is set, but ai-agent-extension is not mounted."
  fi
fi

exec "$@"
