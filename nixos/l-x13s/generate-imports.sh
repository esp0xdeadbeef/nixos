#!/usr/bin/env bash

(
    (
        cd /home/deadbeef/github/nixos/nixos/l-x13s
        find . | grep -v 'old\|./configuration.nix$' | grep 'nix$'| while read line;
        do
            echo "    $line"
        done
    ) | sort
    echo # empty row
    (
        cd /home/deadbeef/github/nixos/nixos/1-general
        find ../1-general | grep '\.nix$' | grep -v '/build_' | grep -v mxbuild | grep -v 'llms\|is-vm\|virtualization\|not-on-aarch64\|work\|werk' | while read line;
        do
            echo "    $line"
        done
    ) | sort
) | tee /tmp/includes-l-werk.txt

awk -v r="$(</tmp/includes-l-werk.txt)" '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' configuration.nix.template >configuration.nix

