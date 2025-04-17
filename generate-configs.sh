#!/usr/bin/env bash

export CURRENT_CONFIG="l-esp"
(
    (
        cd /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd /home/deadbeef/github/nixos/nixos/1-general
        find ../1-general | grep '\.nix$' | grep -v 'llms\|is-vm\|/work/\|/werk/\|autologin\|mxbuild' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/build_configuration.nix > /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/configuration.nix

export CURRENT_CONFIG="l-werk"
(
    (
        cd /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd /home/deadbeef/github/nixos/nixos/1-general
        find ../1-general | grep '\.nix$' | grep -v '/build_' | grep -v 'is-vm\|autologin\|usb-firewall.nix' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_'  | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/build_configuration.nix > /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/configuration.nix

export CURRENT_CONFIG="l-x13s"

(
    (
        cd /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$'| while read line;
        do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd /home/deadbeef/github/nixos/nixos/1-general
        find ../1-general | grep '\.nix$' | grep -v '/build_' | grep -v mxbuild | grep -v 'llms\|is-vm\|virtualization\|not-on-aarch64\|/work\|/werk\|1-custom-packages' | while read line;
        do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_'  | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/build_configuration.nix > /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/configuration.nix

export CURRENT_CONFIG="s-router-vpn-1"
(
    (
        cd /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd /home/deadbeef/github/nixos/nixos/1-general
        find ../1-general | grep '\.nix$' | grep -v '/build_' | grep -v 'is-vm\|autologin\|usb-firewall.nix\|/virtualization/\|llms\|/network/\|browsers\|graphics\|pdf\|rdp\|scripting-languages\|window-managers\|darkmode\|pentesting\|usb-tools\|1-custom-packages\|services/\|audio\|nix-specific' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/build_configuration.nix >  /home/deadbeef/github/nixos/nixos/$CURRENT_CONFIG/configuration.nix

