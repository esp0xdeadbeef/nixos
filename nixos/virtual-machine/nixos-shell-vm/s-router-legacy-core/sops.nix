{ ... }:
{
  #### Secrets (activation-time, not evaluation-time)
  sops.secrets.pppoe-username = {
    owner = "root";
    mode = "0400";
  };

  sops.secrets.pppoe-password = {
    owner = "root";
    mode = "0400";
  };
  sops.secrets.subnet-ipv6 = {
    owner = "root";
    mode = "0400";
  };
}
