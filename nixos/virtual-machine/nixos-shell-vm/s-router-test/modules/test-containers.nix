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

  client2-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "client2";

    config = mkTenantEndpoint "client2";
  };

  mgmt-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "mgmt";

    config = mkTenantEndpoint "mgmt";
  };
}
