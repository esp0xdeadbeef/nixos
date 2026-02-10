{
  config,
  lib,
  outPath,
  ...
}:

let
  generated = import "${outPath}/library/100-fabric-routing/generated" { inherit lib; };
  renderer = import "${outPath}/library/100-fabric-routing/lib/render-networkd" { inherit lib; };

  rendered = renderer.render {
    all = generated.all;
    topologyRaw = generated.topologyRaw;
    nodeName = config.networking.hostName;
  };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs = rendered.netdevs;
  systemd.network.networks = rendered.networks;
}
