# ~/github/nixos/library/100-fabric-routing/inputs/default.nix

let
  base = rec {
    tenantVlans = [
      10
      20
      30
      40
      50
      60
      70
      80
    ];

    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";

    policyAccessTransitBase = 100;
    policyAccessOffset = 0;

    corePolicyTransitVlan = 200;

    defaultRouteMode = "default";

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 4;
        name = "isp-1";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr4 = "10.11.0.50/24";
            addr6 = "fd11:dead:beef:0:7464:55fe:8745:d98c/64";

            routes4 = [
              { dst = "0.0.0.0/0"; via4 = "10.11.0.1"; }
            ];

            routes6 = [
              { dst = "::/0"; }
            ];
          };
        };
      };

      isp-2 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 5;
        name = "isp-2";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr6 = "2001:db8:2::2/48";

            routes6 =
              if defaultRouteMode == "default" then
                [
                  { dst = "::/0"; }
                ]
              else
                [ ];
          };
        };
      };
    };
  };
in
base
// {
  sopsData = { };

  __functor =
    _self: { sopsData ? { } }:
    base
    // sopsData
    // {
      inherit sopsData;
    };
}

