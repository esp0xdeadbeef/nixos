{...}:
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
}
