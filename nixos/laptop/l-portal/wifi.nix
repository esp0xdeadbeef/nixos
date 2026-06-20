{ config
, lib
, pkgs
, outPath
, ...
}:

let
  sopsFile = "${outPath}/secrets/${config.networking.hostName}-default.yaml";

  # SOPS keeps key names in plaintext, so we can safely discover:
  #   wifi-mac
  #   wifi-<name>-ssid
  #   wifi-<name>-password
  #   wifi-<name>-key-mgmt
  #
  # Example:
  #   wifi-h-h-ssid
  #   wifi-h-h-password
  keyFromLine =
    line:
    let
      match = builtins.match "^([A-Za-z0-9_-]+):.*$" line;
    in
    if match == null then null else builtins.elemAt match 0;

  sopsKeys = lib.filter (key: key != null) (
    map keyFromLine (lib.splitString "\n" (builtins.readFile sopsFile))
  );

  wifiSecretNames = lib.filter
    (
      key: key == "wifi-mac" || builtins.match "^wifi-.*-(ssid|password|key-mgmt)$" key != null
    )
    sopsKeys;
in
{
  sops.secrets = lib.genAttrs wifiSecretNames (_: {
    inherit sopsFile;
    owner = "root";
    group = "root";
    mode = "0400";
  });

  systemd.services.networkmanager-ensure-wifi-profiles = {
    description = "Create NetworkManager Wi-Fi profiles from SOPS secrets";
    wantedBy = [
      "multi-user.target"
      "NetworkManager-wait-online.service"
    ];

    after = [
      "NetworkManager.service"
      "sops-nix.service"
    ];

    before = [ "NetworkManager-wait-online.service" ];

    wants = [
      "NetworkManager.service"
      "sops-nix.service"
    ];

    serviceConfig = {
      Type = "oneshot";
    };

    path = with pkgs; [
      coreutils
      gnugrep
      networkmanager
    ];

    script = ''
      set -euo pipefail

      secrets_dir="/run/secrets"
      mac_file="${config.sops.secrets."wifi-mac".path}"

      mac="$(tr -d '\n\r ' < "$mac_file")"

      if ! printf '%s\n' "$mac" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        echo "Invalid MAC address in $mac_file: $mac" >&2
        exit 1
      fi

      found_any=0

      for ssid_file in "$secrets_dir"/wifi-*-ssid; do
        [ -e "$ssid_file" ] || continue

        found_any=1

        ssid_key="$(basename "$ssid_file")"
        prefix="''${ssid_key%-ssid}"
        password_file="$secrets_dir/''${prefix}-password"
        key_mgmt_file="$secrets_dir/''${prefix}-key-mgmt"

        if [ ! -e "$password_file" ]; then
          echo "Missing password secret for $ssid_key: expected ''${prefix}-password" >&2
          continue
        fi

        ssid="$(tr -d '\n\r' < "$ssid_file")"
        password="$(tr -d '\n\r' < "$password_file")"
        key_mgmt="sae"

        if [ -e "$key_mgmt_file" ]; then
          key_mgmt="$(tr -d '\n\r ' < "$key_mgmt_file")"
        fi

        case "$key_mgmt" in
          sae|wpa-psk) ;;
          *)
            echo "Unsupported key management in $key_mgmt_file: $key_mgmt" >&2
            exit 1
            ;;
        esac

        # Use the secret prefix as connection id, not the real SSID.
        # Example: wifi-h-h
        conn_id="$prefix"

        if nmcli -t -f NAME connection show | grep -Fxq "$conn_id"; then
          echo "Updating Wi-Fi profile: $conn_id"
        else
          echo "Creating Wi-Fi profile: $conn_id"
          nmcli connection add \
            type wifi \
            ifname "*" \
            con-name "$conn_id" \
            ssid "$ssid"
        fi

        nmcli connection modify "$conn_id" \
          connection.autoconnect yes \
          connection.autoconnect-priority 100 \
          connection.permissions "" \
          802-11-wireless.ssid "$ssid" \
          802-11-wireless.cloned-mac-address "$mac" \
          802-11-wireless-security.key-mgmt "$key_mgmt" \
          802-11-wireless-security.psk "$password" \
          ipv4.method auto \
          ipv4.may-fail no \
          ipv6.method auto \
          ipv6.may-fail yes
      done

      if [ "$found_any" -eq 0 ]; then
        echo "No wifi-*-ssid secrets found in $secrets_dir" >&2
      fi
    '';
  };
}
