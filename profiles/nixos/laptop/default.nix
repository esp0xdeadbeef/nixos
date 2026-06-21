{ profiles, ... }:
{
  imports = [
    profiles.nixos.laptop.autorandr-default
    profiles.nixos.laptop.dock
    profiles.nixos.laptop.power
    profiles.nixos.laptop.xlayoutdisplay-hotplug
    profiles.nixos.llm-clients.agents
  ];

  local.shell.zshPrompt = {
    enable = true;
  };
}
