{ nebulaRenderer
, peerNebulaCoreName
, pkgs
, plan
, runtimeListenHost
,
}:
nebulaRenderer.buildNebulaBootstrapNixosModule {
  inherit pkgs;
  nebulaRuntimePlan = plan;
  externalLighthousePublicIpv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
  externalLighthousePublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
  externalPortForwardPublicIpv4SecretPath = "/run/secrets/hetzner-public-ipv4";
  externalPortForwardPublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
  externalPortForwardNodeNames = [ ];
  externalRuntimeNodeNames = [ peerNebulaCoreName ];
  runtimeListenHosts.${peerNebulaCoreName} = runtimeListenHost;
  externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
  externalRemoteLighthouseEndpoint6 = "";
  externalSuppressPublicLighthouseStaticMap = true;
  sopsProfileSecretPrefix = "nebula-profile";
  profileSecretMaterializationMode = "sops-runtime";
}
