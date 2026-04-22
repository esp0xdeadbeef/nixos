{ mkTenantEndpoint }:
{
  admin-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "admin";

    config = mkTenantEndpoint "admin";
  };

  client-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "client";

    config = mkTenantEndpoint "client";
  };

  mgmt-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "mgmt";

    config = mkTenantEndpoint "mgmt";
  };
}
