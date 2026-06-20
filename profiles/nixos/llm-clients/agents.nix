{ inputs, pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

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
