#!/usr/bin/env bash

if rsync -va /home/deadbeef/github/nixos deadbeef@s-test-vm:~/github/ | grep -q 'nixos/'; then
  echo switching and rebooting...
  ssh deadbeef@s-test-vm 'sudo nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname) --no-write-lock-file' && ssh deadbeef@s-test-vm 'sudo reboot' && echo "rebooting!" && sleep 30
else
  echo sleeping:
  sleep 2
fi
