#!/usr/bin/env bash

# Get GPU load percentage
#GPU_LOAD_nvidia=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
GPU_LOAD_amd=$(rocm-smi --showuse | grep "GPU use" | rev | awk '{print $1}')

GPU_LOAD=$(echo $GPU_LOAD_amd)
# Determine the state based on GPU load percentage
if [ "$GPU_LOAD" -le 25 ]; then
  STATE="Idle"
  TEXT=""
elif [ "$GPU_LOAD" -le 50 ]; then
  STATE="Info"
  TEXT=""
elif [ "$GPU_LOAD" -le 75 ]; then
  STATE="Good"
  TEXT=""
elif [ "$GPU_LOAD" -le 90 ]; then
  STATE="Warning"
  TEXT=""
else
  STATE="Critical"
  TEXT=""
fi
TEXT="GPU: $GPU_LOAD%"
# Output the JSON block
echo "{\"icon\":\"\",\"state\":\"$STATE\", \"text\": \"$TEXT\"}"

