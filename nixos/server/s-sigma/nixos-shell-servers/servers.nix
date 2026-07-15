{ lib
, pkgs
, self
, config
, ...
}:
# for testing, use:
# nix run path:/home/deadbeef/github/nixos#nixosConfigurations.<vm-hostname>.config.system.build.nixos-shell
# or:
# export HOST="<vm-hostname>" ; nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname) && grep build $(systemctl cat $HOST-image.service | grep Exec | cut -d '=' -f 2) | bash && systemctl restart -- $(ls /etc/systemd/system/s-*-image.service 2>/dev/null | xargs -n1 basename)
let
  mkVM = import "${self.outPath}/profiles/nixos/vm-host/nixos-shell/mk-vm.nix" {
    inherit config pkgs lib self;
  };

  vms = [
    {
      name = "s-infra";
      args = {
        description = "Infra VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-infra"}";
      };
    }
    {
      name = "s-nebula";
      args = {
        description = "Nebula VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-nebula"}";
      };
    }
    {
      name = "s-agents";
      args = {
        description = "Agent workbench VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-agents"}";
      };
    }
    {
      name = "s-router-prod";
      args = {
        autoStart = false;
        description = "Production router canary VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-router-prod"}";
      };
    }
    {
      name = "s-router-legacy-edge";
      args = {
        autoStart = false;
        description = "s-router-legacy-edge VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-router-legacy-edge"}";
      };
    }
    {
      name = "s-router-legacy-core";
      args = {
        autoStart = false;
        description = "s-router-core VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-router-legacy-core"}";
      };
    }
    # {
    #   name = "s-router-core";
    #   args = {
    #     description = "s-router-core VM (nixos-shell)";
    #     repository = "path:${self.lib.vmSourceForHost "s-router-core"}";
    #   };
    # }
    # {
    #   name = "s-router-upstream-selector";
    #   args = {
    #     description = "s-router-upstream-selector VM (nixos-shell)";
    #     repository = "path:${self.lib.vmSourceForHost "s-router-upstream-selector"}";
    #   };
    # }
    # {
    #   name = "s-router-policy";
    #   args = {
    #     description = "s-router-policy VM (nixos-shell)";
    #     repository = "path:${self.lib.vmSourceForHost "s-router-policy"}";
    #   };
    # }
    # {
    #   name = "s-router-access";
    #   args = {
    #     description = "s-router-access VM (nixos-shell)";
    #     repository = "path:${self.lib.vmSourceForHost "s-router-access"}";
    #   };
    # }
    {
      name = "s-router-clab";
      args = {
        description = "s-router-clab VM (nixos-shell)";
        registerImage = true;
        rebuildFromLatestLocks = true;
        repository = "path:${self.lib.vmSourceForHost "s-router-clab"}";
      };
    }
    {
      name = "s-router-nixos";
      args = {
        description = "s-router-nixos VM (nixos-shell)";
        registerImage = true;
        rebuildFromLatestLocks = true;
        repository = "path:${self.lib.vmSourceForHost "s-router-nixos"}";
      };
    }
    {
      name = "s-router-test-clients";
      args = {
        description = "s-router-test-clients VM (nixos-shell)";
        registerImage = true;
        rebuildFromLatestLocks = true;
        repository = "path:${self.lib.vmSourceForHost "s-router-test-clients"}";
      };
    }
    {
      name = "s-router-vpn-egress";
      args = {
        description = "VPN-egress VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-router-vpn-egress"}";
      };
    }
    {
      name = "s-gameserver";
      args = {
        description = "Gameserver VM (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-gameserver"}";
      };
    }
    {
      name = "s-test";
      args = {
        description = "s-test (nixos-shell)";
        repository = "path:${self.lib.vmSourceForHost "s-test"}";
      };
    }
  ];

  managedRunnerHosts = [
    "s-router-clab"
    "s-router-nixos"
    "s-router-test-clients"
  ];

  runnerWrapper = host: pkgs.writeShellScript "run-${host}" ''
    exec /run/current-system/sw/bin/run-vm ${lib.escapeShellArg host} "$@"
  '';

  prodRunner = pkgs.writeShellApplication {
    name = "restart-s-router-prod";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.procps
      pkgs.systemd
      pkgs.tmux
      pkgs.util-linux
    ];
    text = ''
      export S_ROUTER_PROD_FLAKE=${lib.escapeShellArg "path:${self.lib.vmSourceForHost "s-router-prod"}"}
      ${builtins.readFile ./restart-s-router-prod.sh}
    '';
  };

  mkImage = vm: {
    inherit (vm) name;
    value = self.nixosConfigurations.${vm.name}.config.system.build.nixos-shell;
  };

  mkService = vm:
    mkVM vm.name (vm.args // {
      registerImage = vm.args.registerImage or false;
    });
in
{
  config = lib.mkMerge (
    [
      {
        system.build.restartSRouterProd = prodRunner;
        system.build.vmImages = lib.listToAttrs (map mkImage vms);
        systemd.tmpfiles.rules =
          (map
            (host: "L+ /root/${host}.sh - - - - ${runnerWrapper host}")
            managedRunnerHosts)
          ++ [ "L+ /root/s-router-prod.sh - - - - ${lib.getExe prodRunner}" ];
      }
    ]
    ++ map mkService vms
  );
}
