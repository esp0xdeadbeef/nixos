#!/usr/bin/env bash

# nixos config:
export CURRENT_CONFIG="l-esp"
echo "nixos config $CURRENT_CONFIG"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix > .//nixos/$CURRENT_CONFIG/configuration.nix

echo homemanager $CURRENT_CONFIG:
# homemanager config:
(
    (
        cd ./home-manager/$CURRENT_CONFIG
        find . | grep -v 'old\|./home.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd ./home-manager/01-general
        find ../01-general | grep '\.nix$' | grep -v 'llms\|is-vm\|/work/\|/werk/\|autologin\|mxbuild' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_\|home.nix$' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' ./home-manager/$CURRENT_CONFIG/build_home.nix > ./home-manager/$CURRENT_CONFIG/home.nix

export CURRENT_CONFIG="l-werk"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v 'is-vm\|autologin\|usb-firewall.nix\|garbage-collection.nix' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_'  | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix > .//nixos/$CURRENT_CONFIG/configuration.nix


echo homemanager $CURRENT_CONFIG:
(
    (
        cd ./home-manager/$CURRENT_CONFIG
        find . | grep -v 'old\|./home.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd ./home-manager/01-general
        find ../01-general | grep '\.nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_\|home.nix$' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' ./home-manager/$CURRENT_CONFIG/build_home.nix > ./home-manager/$CURRENT_CONFIG/home.nix


export CURRENT_CONFIG="l-werk-1"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v 'is-vm\|autologin\|usb-firewall.nix\|garbage-collection.nix' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_'  | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix > .//nixos/$CURRENT_CONFIG/configuration.nix


echo homemanager $CURRENT_CONFIG:
(
    (
        cd ./home-manager/$CURRENT_CONFIG
        find . | grep -v 'old\|./home.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd ./home-manager/01-general
        find ../01-general | grep '\.nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_\|home.nix$' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' ./home-manager/$CURRENT_CONFIG/build_home.nix > ./home-manager/$CURRENT_CONFIG/home.nix



export CURRENT_CONFIG="l-x13s"

(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$'| while read line;
        do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v mxbuild | grep -v 'llms\|is-vm\|virtualization\|not-on-aarch64\|/work\|/werk\|1-custom-packages' | while read line;
        do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_'  | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix > .//nixos/$CURRENT_CONFIG/configuration.nix

export CURRENT_CONFIG="s-router-vpn-1"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v 'usb-firewall.nix\|/virtualization/\|llms\|/network/\|browsers\|graphics\|pdf\|rdp\|scripting-languages\|darkmode\|pentesting\|usb-tools\|1-custom-packages\|services/\|audio\|nix-specific' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix >  .//nixos/$CURRENT_CONFIG/configuration.nix



export CURRENT_CONFIG="s-test-vm"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v 'usb-firewall.nix\|/virtualization/\|llms\|browsers\|graphics\|pdf\|rdp\|scripting-languages\|pentesting\|usb-tools\|1-custom-packages\|services/\|audio' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix >  .//nixos/$CURRENT_CONFIG/configuration.nix


export CURRENT_CONFIG="s-test-vm-impermanence"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_' | grep -v 'usb-firewall.nix\|/virtualization/\|llms\|browsers\|graphics\|pdf\|rdp\|scripting-languages\|pentesting\|usb-tools\|1-custom-packages\|services/\|audio' | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix >  .//nixos/$CURRENT_CONFIG/configuration.nix

export CURRENT_CONFIG="s-lxc-test"
(
    (
        cd .//nixos/$CURRENT_CONFIG
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$' | while read line; do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd .//nixos/01-general
        find ../01-general | grep '\.nix$' | grep -v '/build_'  | while read line; do
            echo "    $line"
        done
    ) | sort
) | grep -v '/build_' | tee /tmp/results.txt

awk -v r="$(</tmp/results.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' .//nixos/$CURRENT_CONFIG/build_configuration.nix >  .//nixos/$CURRENT_CONFIG/configuration.nix

