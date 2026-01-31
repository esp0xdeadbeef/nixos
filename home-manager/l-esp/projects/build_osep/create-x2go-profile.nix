{
  config,
  pkgs,
  lib,
  ...
}:

let
  updateX2GoSession = pkgs.writeShellScriptBin "update-x2go-session" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_DIR="$HOME/.x2goclient"
    SESSION_FILE="$SESSION_DIR/sessions"
    ID_FILE="$HOME/x2go-session-identifier"

    # make sure the session file exists
    mkdir -p "$SESSION_DIR" || true
    touch "$SESSION_FILE"

    # grab the current container IP (adjust container name & iface if needed)
    IP="$(lxc-attach osep-lxc -- ip -4 addr show eth0 \
      | sed -n 's/.*inet \([0-9\.]\+\)\/.*/\1/p' | tr -d '\n')"

    if [[ -z "$IP" ]]; then
      echo "error: could not determine container IP" >&2
      exit 1
    fi

    # if we already have a session for this IP, extract its ID
    if grep -q "host=$IP" "$SESSION_FILE"; then
      ID=$(awk -v ip="$IP" '
        $0 ~ /^\[.*\]$/ { last=$0 }
        $0 ~ "host="ip { gsub(/[][]/,"",last); print last; exit }
      ' "$SESSION_FILE")
      echo "$ID" > "$ID_FILE"
      echo "found existing x2go session: $ID"
      exit 0
    fi

    # otherwise generate a new timestamp ID and append a block
    ID=$(date +%Y%m%d%H%M%S%N)
    session_name="x2go-session-$ID"
    {
      printf "[%s]\n" "$ID"
      cat <<EOF
    applications=WWWBROWSER, MAILCLIENT, OFFICE, TERMINAL
    autologin=true
    clipboard=both
    command="startxfce4 & ; /usr/bin/xfconf-query -c xfwm4 -p /general/use_compositing -s false ; startxfce4"
    defsndport=true
    directrdp=false
    directrdpsettings=
    directxdmcp=false
    directxdmcpsettings=
    display=1
    dpi=142
    export=
    fstunnel=true
    fullscreen=false
    height=600
    host=$IP
    icon=:/img/icons/128x128/x2gosession.png
    iconvfrom=ISO8859-1
    iconvto=UTF-8
    kdrive=false
    key=$HOME/.ssh/id_rsa_lxc
    krbdelegation=false
    krblogin=false
    maxdim=false
    multidisp=false
    name=$session_name
    pack=16m-jpeg
    print=true
    published=false
    quality=9
    rdpclient=rdesktop
    rdpoptions=
    rdpport=3389
    rdpserver=
    rootless=false
    setdpi=true
    sndport=4713
    sound=true
    soundsystem=pulse
    soundtunnel=true
    speed=2
    sshport=22
    sshproxyautologin=false
    sshproxyhost=
    sshproxykeyfile=
    sshproxykrblogin=false
    sshproxyport=22
    sshproxysamepass=false
    sshproxysameuser=false
    sshproxytype=SSH
    sshproxyuser=
    startsoundsystem=true
    type=auto
    useiconv=false
    usekbd=true
    user=$(whoami)
    usesshproxy=false
    width=800
    xdmcpclient=Xnest
    xdmcpserver=localhost
    xinerama=false
    EOF
      echo
    } >> "$SESSION_FILE"

    entry=$(lxc-attach osep-lxc -- bash -c "ip a s eth0 | sed -n 's/.*inet \([0-9\.]\+\)\/.*/\1/p' | tr -d '\n' ; echo -n ' ' ; cat /etc/ssh/ssh_host_rsa_key.pub")

    if ! grep -Fxq "$entry" "$HOME/.ssh/known_hosts"; then
        echo "$entry" >> "$HOME/.ssh/known_hosts"
    fi

    echo "x2goclient --session='$session_name' --hide" > "$ID_FILE"
    chmod +x "$ID_FILE"
    "$ID_FILE"
  '';
in
{
  # install the little updater script into your user PATH
  home.packages = [ updateX2GoSession ];

  systemd.user.services."updateX2GOSession" = {
    Unit = {
      Description = "update the x2go session file";
      # After = [ "network-online.target" ];
      # Wants = [ "network-online.target" ];
      After = [ "graphical-session.target" ];
      Wants = [
        "graphical-session.target"
        "network-online.target"
      ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [

      ];
      #       ExecStart = "${pkgs.writeShellScript "updateX2GOSession-callee" ''
      # #!${pkgs.bash}/bin/bash --noprofile --norc
      # ${updateX2GoSession}/bin/update-x2go-session
      #       ''}";
      ExecStart = "${updateX2GoSession}/bin/update-x2go-session";
      Restart = "on-failure";
      RestartSec = "10s"; # back off between retries
      TimeoutStartSec = "75s";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
