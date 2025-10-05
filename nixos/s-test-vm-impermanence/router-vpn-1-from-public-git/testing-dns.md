[root@lan-to-vpn-airvpn:~]# resolvectl -j show-server-state | jq '.["Interface" = tun0]'
jq: command not found

[root@lan-to-vpn-airvpn:~]# resolvectl -j show-server-state | nix shell nixpkgs#jq -- jq '.[] | select(.Interface == "tun0")'
error: experimental Nix feature 'nix-command' is disabled; add '--extra-experimental-features nix-command' to enable it
[root@lan-to-vpn-airvpn:~]# resolvectl -j show-server-state | nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq -- jq '.[] | select(.Interface == "tun0")'
error: getting status of '/root/.[] | select(.Interface == "tun0")': No such file or directory
[root@lan-to-vpn-airvpn:~]# resolvectl -j show-server-state | nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq ^C jq '.[] | select(.Interface == "tun0")'

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\")"'
{
  "Server": "10.128.0.1",
  "Type": "link",
  "Interface": "tun0",
  "InterfaceIndex": 5,
  "VerifiedFeatureLevel": "UDP+EDNS0",
  "PossibleFeatureLevel": "UDP+EDNS0",
  "DNSSECMode": "no",
  "DNSSECSupported": true,
  "ReceivedUDPFragmentMax": 512,
  "FailedUDPAttempts": 0,
  "FailedTCPAttempts": 0,
  "PacketTruncated": false,
  "PacketBadOpt": false,
  "PacketRRSIGMissing": false,
  "PacketInvalid": false,
  "PacketDoOff": false
}
{
  "Server": "fd7d:76ee:e68f:a993::1",
  "Type": "link",
  "Interface": "tun0",
  "InterfaceIndex": 5,
  "VerifiedFeatureLevel": "n/a",
  "PossibleFeatureLevel": "TLS+EDNS0+DO",
  "DNSSECMode": "no",
  "DNSSECSupported": true,
  "ReceivedUDPFragmentMax": 512,
  "FailedUDPAttempts": 0,
  "FailedTCPAttempts": 0,
  "PacketTruncated": false,
  "PacketBadOpt": false,
  "PacketRRSIGMissing": false,
  "PacketInvalid": false,
  "PacketDoOff": false
}

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\").Server"'
"10.128.0.1"
"fd7d:76ee:e68f:a993::1"

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\").Server"' | grep .
"10.128.0.1"
"fd7d:76ee:e68f:a993::1"

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\").Server"' | grep \..
"10.128.0.1"
"fd7d:76ee:e68f:a993::1"

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\").Server"' | grep \.
"10.128.0.1"
"fd7d:76ee:e68f:a993::1"

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq ".[] | select(.Interface == \"tun0\").Server"' | grep "\."
"10.128.0.1"

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq -v ".[] | select(.Interface == \"tun0\").Server"' | grep "\."
jq: Unknown option -v
Use jq --help for help with command-line options,
or see the jq manpage, or online docs  at https://jqlang.org

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq -r ".[] | select(.Interface == \"tun0\").Server"' | grep "\."
10.128.0.1

[root@lan-to-vpn-airvpn:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#jq --command bash -c 'resolvectl -j show-server-state | jq -r ".[] | select(.Interface == \"tun0\").Server" | grep "\." '
10.128.0.1

[root@lan-to-vpn-airvpn:~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: lan-airvpn@if14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether e2:89:12:f2:ae:80 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.90.0.1/24 brd 10.90.0.255 scope global lan-airvpn
       valid_lft forever preferred_lft forever
    inet6 fd90:dead:beef::1/64 scope global
       valid_lft forever preferred_lft forever
    inet6 fe80::e089:12ff:fef2:ae80/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
3: wan-airvpn@if15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 92:09:d7:a5:d6:bd brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.30.0.141/24 metric 1024 brd 10.30.0.255 scope global dynamic wan-airvpn
       valid_lft 345sec preferred_lft 345sec
    inet6 fd30:dead:beef:0:7fbf:5bca:2e32:431d/64 scope global temporary dynamic
       valid_lft 86400sec preferred_lft 14400sec
    inet6 fd30:dead:beef:0:9009:d7ff:fea5:d6bd/64 scope global dynamic mngtmpaddr noprefixroute
       valid_lft 86400sec preferred_lft 14400sec
    inet6 fe80::9009:d7ff:fea5:d6bd/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
5: tun0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1320 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 10.138.97.20/32 scope global tun0
       valid_lft forever preferred_lft forever
    inet6 fd7d:76ee:e68f:a993:ce12:35fe:1dfb:e8b8/128 scope global
       valid_lft forever preferred_lft forever

[root@lan-to-vpn-airvpn:~]# ip a | grep global
    inet 10.90.0.1/24 brd 10.90.0.255 scope global lan-airvpn
    inet6 fd90:dead:beef::1/64 scope global
    inet 10.30.0.141/24 metric 1024 brd 10.30.0.255 scope global dynamic wan-airvpn
    inet6 fd30:dead:beef:0:7fbf:5bca:2e32:431d/64 scope global temporary dynamic
    inet6 fd30:dead:beef:0:9009:d7ff:fea5:d6bd/64 scope global dynamic mngtmpaddr noprefixroute
    inet 10.138.97.20/32 scope global tun0
    inet6 fd7d:76ee:e68f:a993:ce12:35fe:1dfb:e8b8/128 scope global

[root@lan-to-vpn-airvpn:~]# ip a | grep global | grep scope
    inet 10.90.0.1/24 brd 10.90.0.255 scope global lan-airvpn
    inet6 fd90:dead:beef::1/64 scope global
    inet 10.30.0.141/24 metric 1024 brd 10.30.0.255 scope global dynamic wan-airvpn
    inet6 fd30:dead:beef:0:7fbf:5bca:2e32:431d/64 scope global temporary dynamic
    inet6 fd30:dead:beef:0:9009:d7ff:fea5:d6bd/64 scope global dynamic mngtmpaddr noprefixroute
    inet 10.138.97.20/32 scope global tun0
    inet6 fd7d:76ee:e68f:a993:ce12:35fe:1dfb:e8b8/128 scope global

[root@lan-to-vpn-airvpn:~]# ip -6 a s lan
Device "lan" does not exist.

[root@lan-to-vpn-airvpn:~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: lan-airvpn@if14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether e2:89:12:f2:ae:80 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.90.0.1/24 brd 10.90.0.255 scope global lan-airvpn
       valid_lft forever preferred_lft forever
    inet6 fd90:dead:beef::1/64 scope global
       valid_lft forever preferred_lft forever
    inet6 fe80::e089:12ff:fef2:ae80/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
3: wan-airvpn@if15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 92:09:d7:a5:d6:bd brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.30.0.141/24 metric 1024 brd 10.30.0.255 scope global dynamic wan-airvpn
       valid_lft 600sec preferred_lft 600sec
    inet6 fd30:dead:beef:0:7fbf:5bca:2e32:431d/64 scope global temporary dynamic
       valid_lft 86398sec preferred_lft 14398sec
    inet6 fd30:dead:beef:0:9009:d7ff:fea5:d6bd/64 scope global dynamic mngtmpaddr noprefixroute
       valid_lft 86398sec preferred_lft 14398sec
    inet6 fe80::9009:d7ff:fea5:d6bd/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
5: tun0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1320 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 10.138.97.20/32 scope global tun0
       valid_lft forever preferred_lft forever
    inet6 fd7d:76ee:e68f:a993:ce12:35fe:1dfb:e8b8/128 scope global
       valid_lft forever preferred_lft forever

[root@lan-to-vpn-airvpn:~]# ip -6 a s lan-airvpn
2: lan-airvpn@if14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000 link-netnsid 0
    inet6 fd90:dead:beef::1/64 scope global
       valid_lft forever preferred_lft forever
    inet6 fe80::e089:12ff:fef2:ae80/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever

[root@lan-to-vpn-airvpn:~]# ip -6 a s lan-airvpn | grep 'scope global'
    inet6 fd90:dead:beef::1/64 scope global

[root@lan-to-vpn-airvpn:~]#