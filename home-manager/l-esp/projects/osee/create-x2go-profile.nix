{ config
, pkgs
, lib
, ...
}:

let
  # Resolve lxc-osee's IPv4 address on eth0 and wait until sshd in the container
  # accepts connections.
  #
  # Scoped to `dev eth0` on purpose: lxc-info -i and a bare `ip -4 addr` also
  # report the container's docker0/br-* addresses, which are not reachable from
  # the host and must never end up in an x2go session.
  #
  # The address itself is assigned by LXC (lxc.net.0.ipv4.address), so this wait
  # is about the container finishing boot, not about DHCP.
  waitForContainerIp = ''
    IP=""
    for _ in $(seq 1 60); do
      IP="$(${pkgs.lxc}/bin/lxc-attach lxc-osee -- \
        ip -4 -o addr show dev eth0 2>/dev/null \
        | awk '{ split($4, a, "/"); print a[1]; exit }' || true)"
      [[ -n "$IP" ]] && break
      sleep 2
    done
  '';

  # One-shot readiness gate for the container. updateX2GOSession is ordered
  # After= this unit, so on a cold boot it no longer races the container:
  # eth0 has an address and sshd is reachable before the session file is
  # written. lxc-osee-start.service itself is left alone -- it keeps running
  # `lxc-start -F` in the foreground, which is what keeps the container in a
  # sane cgroup.
  waitForContainerIpUnit = pkgs.writeShellScriptBin "wait-for-lxc-osee-ip" ''
    set -euo pipefail

    ${waitForContainerIp}

    if [[ -z "$IP" ]]; then
      echo "error: lxc-osee has no IPv4 address on eth0 after 120s" >&2
      echo "hint: the address is assigned by LXC via lxc.net.0.ipv4.address in" >&2
      echo "      ~/.local/share/lxc/lxc-osee/config; check that it is present and" >&2
      echo "      that 'lxc-info -n lxc-osee -s' reports RUNNING." >&2
      exit 1
    fi

    # The container may have an address before sshd is listening; x2go connects
    # over SSH, so wait for the port too. bash is required for /dev/tcp.
    for _ in $(seq 1 30); do
      if ${pkgs.lxc}/bin/lxc-attach -n lxc-osee -- \
        bash -c 'exec 3<>/dev/tcp/127.0.0.1/22' 2>/dev/null; then
        echo "lxc-osee eth0 is up with $IP and sshd is accepting connections"
        exit 0
      fi
      sleep 2
    done

    echo "error: lxc-osee sshd is not accepting connections (ip $IP)" >&2
    exit 1
  '';

  updateX2GoSession = pkgs.writeShellScriptBin "update-x2go-session" ''
    set -euo pipefail

    SESSION_DIR="$HOME/.x2goclient"
    SESSION_FILE="$SESSION_DIR/sessions"
    ID_FILE="$HOME/x2go-session-identifier"

    # make sure the session file exists
    mkdir -p "$SESSION_DIR" || true
    touch "$SESSION_FILE"

    # Resolve the container's eth0 address, waiting for DHCP if needed so this
    # script is also correct when run by hand outside of systemd ordering.
    ${waitForContainerIp}

    if [[ -z "$IP" ]]; then
      echo "error: could not determine container IP on eth0 after 120s" >&2
      echo "hint: the address is assigned by LXC via lxc.net.0.ipv4.address in" >&2
      echo "      ~/.local/share/lxc/lxc-osee/config; check that it is present and" >&2
      echo "      that 'lxc-info -n lxc-osee -s' reports RUNNING." >&2
      exit 1
    fi

    # if we already have a session for this IP, extract its ID
    # If a session for this container already exists, attach to it instead of
    # creating a duplicate. The stored block is keyed by IP; we need its
    # connection *name* (the `name=` line), not the bare block id, because that
    # is what x2goclient --session expects.
    if grep -q "host=$IP" "$SESSION_FILE"; then
      session_name=$(awk -v ip="$IP" '
        function flush() { if (match_host && name != "") { print name; exit } }
        /^\[.*\]$/ { flush(); name = ""; match_host = 0 }
        /^name=/ { name = substr($0, 6) }
        $0 == "host=" ip { match_host = 1 }
        END { flush() }
      ' "$SESSION_FILE")

      if [[ -n "$session_name" ]]; then
        echo "found existing x2go session: $session_name"
        echo "${pkgs.x2goclient}/bin/x2goclient --session='$session_name' --hide" > "$ID_FILE"
        chmod +x "$ID_FILE"
        exec ${pkgs.x2goclient}/bin/x2goclient --session="$session_name" --hide
      fi
      # Block exists but is malformed; fall through and create a fresh one.
      echo "warning: existing entry for host=$IP has no name= line, creating a new session" >&2
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

    # known_hosts entry for this container: "<ip> <ssh host pubkey>".
    # Reuse the IP already resolved above instead of re-parsing eth0, so the two
    # can never disagree.
    entry="$IP $(${pkgs.lxc}/bin/lxc-attach lxc-osee -- cat /etc/ssh/ssh_host_rsa_key.pub)"

    if ! grep -Fxq "$entry" "$HOME/.ssh/known_hosts"; then
        echo "$entry" >> "$HOME/.ssh/known_hosts"
    fi

    echo "${pkgs.x2goclient}/bin/x2goclient --session='$session_name' --hide" > "$ID_FILE"
    chmod +x "$ID_FILE"
    ${pkgs.x2goclient}/bin/x2goclient --session="$session_name" --hide
  '';
in
{
  # install the little updater script into your user PATH
  home.packages = [ updateX2GoSession waitForContainerIpUnit pkgs.x2goclient pkgs.lxc ];

  # Wait until the container's eth0 actually has an address. RemainAfterExit
  # makes the "ready" result sticky for the rest of the graphical session.
  systemd.user.services."waitForLxcOseeIp" = {
    Unit = {
      Description = "Wait for lxc-osee to obtain an IPv4 address on eth0";
      After = [
        "graphical-session.target"
        "lxc-osee-start.service"
      ];
      # lxc-osee-start.service is Type=simple with `lxc-start -F`, so it reports
      # started as soon as lxc-start forks, not when the container is reachable.
      # This unit is the real readiness gate; it polls eth0 itself.
      Wants = [ "lxc-osee-start.service" ];
      PartOf = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${waitForContainerIpUnit}/bin/wait-for-lxc-osee-ip";
      # Bounded by the 60x2s poll loop inside the script.
      TimeoutStartSec = "150s";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services."updateX2GOSession" = {
    Unit = {
      Description = "update the x2go session file";
      After = [
        "graphical-session.target"
        "waitForLxcOseeIp.service"
      ];
      PartOf = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      # Do not start before the container's network is ready: without this a
      # cold boot ran the session writer while eth0 still had no address.
      Wants = [ "waitForLxcOseeIp.service" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${updateX2GoSession}/bin/update-x2go-session";
      Restart = "on-failure";
      RestartSec = "10s";
      # Must not undercut the script's own 120s wait-for-eth0 loop.
      TimeoutStartSec = "150s";
      KillMode = "control-group";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
