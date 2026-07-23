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
  ];

  # Official, locally runnable DeepSeek-V4-Flash GGUF.
  #
  # UD-IQ2_M is approximately 90.9 GB. It is a more defensible choice
  # than IQ1 on a server with roughly 128 GB RAM, while remaining much
  # smaller than the approximately 155 GB Q4_K_XL quant.
  deepseekV4Official = [
    "hf.co/unsloth/DeepSeek-V4-Flash-GGUF:UD-IQ2_M"
  ];

  # Alternative to the official V4 quant, not an additional dependency.
  #
  # Keeping this in a separate profile avoids automatically downloading
  # both approximately 90.9 GB of official V4 and approximately 86.9 GB
  # of abliterated V4 weights.
  deepseekV4Unrestricted = [
    "hf.co/huihui-ai/Huihui-DeepSeek-V4-Flash-abliterated-GGUF:UD-IQ1_M"
  ];

  # Additional CyberNeurova alternative kept out of active profiles until it
  # can be evaluated separately.
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
    ++ deepseekV4Official
    ++ deepseekV4Unrestricted
    ++ deepseekV4CyberNeurova;
}
