{
  # Explicit legacy bridge names (string keys!)
  legacyBridgeNames = {
    "1010" = "br-vlan1010";
  };

  # Legacy LAN VLANs that MUST exist
  legacyLanVlans = [ 1010 ];

  # Transit VLANs (router links)
  transitVlans = [ 100 ];

  # WAN VLAN (PPPoE trunk)
  wanVlan = 6;
}
