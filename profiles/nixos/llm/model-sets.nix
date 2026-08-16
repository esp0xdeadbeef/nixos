let
  # Small enough to keep available on nearly every Ollama host.
  baseline = [
    # General-purpose multimodal model.
    "qwen3.5:9b-q4_K_M"

    # Lightweight helper for coding, classification, and agents.
    "qwen3.5:4b-q4_K_M"

    # Multilingual and code-aware embedding model.
    "qwen3-embedding:0.6b-q8_0"

    # DeepSeek-R1-0528-Qwen3-8B.
    #
    # Unlike the 14B and 32B variants, this one received the R1-0528
    # refresh and is therefore the sensible small DeepSeek baseline.
    "deepseek-r1:8b"
  ];

  workstationExtra = [
    # Models that fit reasonably well on a Tesla P100 with 16 GiB VRAM.
    "gemma4:12b-it-q4_K_M"
    "deepseek-r1:14b-qwen-distill-q4_K_M"

    "hermes3:8b-llama3.1-q4_K_M"
    "dolphin3:8b-llama3.1-q4_K_M"

    # Less refusal-heavy variants.
    "huihui_ai/dolphin3-abliterated:8b-llama3.1-q4_K_M"
    "huihui_ai/gemma-4-abliterated:12b"

    "hf.co/richardyoung/Qwen3-14B-abliterated-GGUF:Q4_K_M"

    # Use the newer v2 abliteration rather than the older repository.
    "hf.co/mradermacher/DeepSeek-R1-Distill-Qwen-14B-abliterated-v2-GGUF:Q4_K_M"
  ];

  heavyExtra = [
    # DeepSeek-R1 32B: approximately 20 GB, so partial CPU/RAM offload
    # is required with a 16 GiB P100.
    "deepseek-r1:32b-qwen-distill-q4_K_M"

    # Local successors to deepseek-coder:33b.
    "qwen3-coder:30b-a3b-q4_K_M"
    "qwen3-coder-next:q4_K_M"

    # Current larger general-purpose and coding-capable models.
    "qwen3.6:27b-q4_K_M"
    "qwen3.6:35b-a3b-q4_K_M"
    "mistral-small3.2:24b"

    # Larger Gemma 4 models.
    "gemma4:26b-a4b-it-q4_K_M"
    "gemma4:31b-it-q4_K_M"

    # These Huihui Qwen 3.6 repositories currently expose Q2_K
    # through their documented Ollama command, not Q4_K_M.
    "hf.co/huihui-ai/Huihui-Qwen3.6-27B-abliterated-MTP-GGUF:Q2_K"
    "hf.co/huihui-ai/Huihui-Qwen3.6-35B-A3B-abliterated-MTP-GGUF:Q2_K"

    # Very large coding model; primarily system-RAM bound on a P100.
    "hf.co/ymsf/Huihui-Qwen3-Coder-Next-Abliterated-GGUF:Q4_K_M"

    # Offensive-security abliterated 35B. The HF proxy rejects the
    # explicit Q4_K tag for this repository, so use "latest", which
    # currently resolves to the Q4_K single-file quant plus its mmproj
    # projector.
    "hf.co/huihui-ai/Huihui-CyberStrike-OffSec-35B-abliterated-GGUF:latest"
  ];

  # Abliterated DeepSeek-V4-Flash GGUF.
  #
  # The unsloth official V4 repository is sharded and cannot be pulled via
  # ollama's registry, and the previous huihui-ai abliterated V4 repository
  # is now gated, so this non-gated CyberNeurova single-file quant is the
  # active V4 variant.
  deepseekV4CyberNeurova = [
    "hf.co/cyberneurova/CyberNeurova-DeepSeek-V4-Flash-abliterated-GGUF:Q2_K"
  ];
in
{
  inherit baseline;

  workstation = baseline ++ workstationExtra;

  heavy =
    baseline
    ++ workstationExtra
    ++ heavyExtra
    ++ deepseekV4CyberNeurova;
}
