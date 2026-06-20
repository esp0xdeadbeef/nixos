{ inputs, pkgs, ... }:
{
  environment.systemPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claw-code
    codex
    crush
    forgecode
    gitclaw
    hermes-agent
    hermes-desktop
    hermes-hud
    mimo-code
    nanocoder
    oh-my-codex
    omp
    openclaw
    opencode
    openfang
    pi
    picoclaw
    reasonix
    vessel-browser
    zeroclaw
  ];
}
