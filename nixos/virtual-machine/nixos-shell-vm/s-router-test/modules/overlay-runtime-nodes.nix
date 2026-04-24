{ renderedHostNetwork }:
if renderedHostNetwork.bridges ? branch then
  {
    nebula-core = {
      enterprise = "esp0xdeadbeef";
      site = "site-a";
      overlay = "east-west";
      groups = [
        "lab"
        "core"
      ];
      container = {
        hostBridge = "br-uplink1";
        profile = "core-client";
      };
    };

    branch-node01 = {
      enterprise = "espbranch";
      site = "site-b";
      overlay = "east-west";
      groups = [
        "lab"
        "branch"
      ];
      container = {
        hostBridge = "branch";
        profile = "branch-web";
      };
    };

    hostile-node01 = {
      enterprise = "espbranch";
      site = "site-b";
      overlay = "east-west";
      groups = [
        "lab"
        "hostile"
      ];
      unsafeRoutes = [
        { route = "0.0.0.0/1"; }
        { route = "128.0.0.0/1"; }
        { route = "::/1"; }
        { route = "8000::/1"; }
      ];
      container = {
        hostBridge = "hostile";
        profile = "hostile-exit";
      };
    };

    nas-node01 = {
      enterprise = "esp0xdeadbeef";
      site = "site-c";
      overlay = "site-c-storage";
      groups = [
        "lab"
        "site-c"
        "storage"
      ];
      container = {
        hostBridge = "nas";
        profile = "storage-client";
      };
    };

    printer-node01 = {
      enterprise = "esp0xdeadbeef";
      site = "site-c";
      overlay = "site-c-storage";
      groups = [
        "lab"
        "site-c"
        "printer"
      ];
      container = {
        hostBridge = "printer";
        profile = "storage-client";
      };
    };
  }
else
  { }
