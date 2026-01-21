{ config, pkgs, ... }:

{
  #############################################
  # Firewall (UniFi)
  #############################################

  networking.firewall.enable = false;

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = false;
  };

  #virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers = {
    backend = "podman";

  };

  #############################################
  # UniFi Controller (container)
  #############################################

  virtualisation.oci-containers.containers.unifi = {
    image = "docker.io/jacobalberty/unifi";
    autoStart = true;

    # IMPORTANT:
    # Do NOT set SYSTEM_IP.
    # UniFi must bind to 0.0.0.0 inside the container.
    environment = {
      TZ = "Africa/Johannesburg";
    };

    ports = [
      "8080:8080"
      "8443:8443"
      "3478:3478/udp"
      "10001:10001/udp"
    ];

    volumes = [
      "/persist/var/lib/unifi:/unifi"
    ];

    extraOptions = [
      "--name=unifi"
      "--user=unifi"
      "--network=host"
      "--init"
    ];
  };

  #############################################
  # Persistence
  #############################################

  systemd.tmpfiles.rules = [
    "d /var/lib/unifi 0755 unifi unifi -"
  ];
}
