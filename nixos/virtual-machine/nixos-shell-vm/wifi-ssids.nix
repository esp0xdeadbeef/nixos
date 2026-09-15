# The cobalt Wi-Fi plane set, declared once and shared by every AP radio.
#
# This is the full set of planes; each AP carries the subset its radio supports
# (a plane is not owned by one radio). The SSID and passphrase are never in the
# Nix store; `ssid` and `pskKey` name how the runtime helper resolves them from
# /run/secrets/cobalt-wifi.
#
# `ssid` encoding:
#   "derive:<plane>" -> deterministic SSID for <plane> (seed + SSID wordlist)
#   "secret:<name>"  -> .<name>.ssid verbatim (a fixed, non-derived SSID)
# `pskKey` selects the .<pskKey>.psk field.
{
  # Deterministic SSID derivation walks this list with one shared "already
  # used" set, so every radio must derive shared planes in the same order or
  # the 2.4GHz and 5GHz BSSes would disagree on the SSID. clients and
  # clients-vpn are served on both radios, so they are derived first.
  deriveOrder = [
    "cobalt-clients"
    "cobalt-clients-vpn"
    "cobalt-mgmt"
  ];

  planes = [
    {
      plane = "cobalt-clients";
      bridge = "ap-clients";
      keyMgmt = "SAE";
      ssid = "derive:cobalt-clients";
      pskKey = "cobalt-clients";
    }
    {
      plane = "cobalt-clients-vpn";
      bridge = "ap-clients-vpn";
      keyMgmt = "SAE";
      ssid = "derive:cobalt-clients-vpn";
      pskKey = "cobalt-clients-vpn";
    }
    {
      plane = "cobalt-mgmt";
      bridge = "ap-mgmt";
      keyMgmt = "WPA-PSK";
      ssid = "derive:cobalt-mgmt";
      pskKey = "cobalt-mgmt";
    }
    {
      plane = "cobalt-unlock";
      bridge = "ap-unlock";
      keyMgmt = "WPA-PSK";
      ssid = "secret:cobalt-unlock";
      pskKey = "cobalt-unlock";
    }
  ];
}
