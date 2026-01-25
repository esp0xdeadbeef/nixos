{ ... }:
{
  systemd.services."valheim-server" = {
    unitConfig = {
      StartLimitIntervalSec = 0;
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  virtualisation.oci-containers.containers.valheim-server = {
    image = "docker.io/lloesche/valheim-server";
    autoStart = true;

    environment = {
      SERVER_NAME = "test-server";
      SERVER_PASS = "abc2222";
      WORLD_NAME = "test-world";
      SERVER_PUBLIC = "true";
    };

    ports = [
      "2456-2458:2456-2458/udp"
    ];

    volumes = [
      "/persist/game-servers/valheim/prod:/config"
    ];

    extraOptions = [
      "--name=valheim-server"
    ];
  };
  systemd.tmpfiles.rules = [
    "d /persist/game-servers/valheim/prod 0755 root root -"
  ];

}
