{pkgs, inputs, ...}:
{
environment.systemPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    opencode
    qwen-code
    codex
    hermes-agent
  ];
}
