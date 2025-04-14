#!/usr/bin/env bash

(
    cd /home/deadbeef/github/nixos/nixos/l-werk
    find . | grep -v 'old\|./configuration.nix$' | grep 'nix$'
)

(
    cd /home/deadbeef/github/nixos/nixos/1-general
    find ../1-general | grep '\.nix$' | grep -v 'is-vm\|autologin\|usb-firewall.nix'
)
