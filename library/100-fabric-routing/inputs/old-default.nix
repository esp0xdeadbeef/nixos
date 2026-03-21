{

  esp0xdeadbeef = {

    site-a = {

      p2p-pool = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      nodes = {

        s-router-core = {
          role = "core";

          wan = { };

        };

        s-router-policy = {
          role = "policy";
        };

        s-router-access = {
          role = "access";

          mgmt = {

            ipv4 = "10.20.10.0/24";
            ipv6 = "fd42:dead:beef:10::/64";
            kind = "client";
          };
          clients = {

            ipv4 = "10.20.20.0/24";
            ipv6 = "fd42:dead:beef:20::/64";
            kind = "client";
          };
        };
      };

      links = [
        [
          "s-router-core"
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-access"
        ]
      ];
    };
  };

}
