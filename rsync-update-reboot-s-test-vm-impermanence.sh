#!/usr/bin/env bash
ssh deadbeef@s-test-vm-impermanence uptime
if rsync -va /home/deadbeef/github/nixos deadbeef@s-test-vm-impermanence:~/github/ | grep -q 'nixos/'; then
  echo switching and rebooting...
  ssh deadbeef@s-test-vm-impermanence 'sudo nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) --no-write-lock-file' && ssh deadbeef@s-test-vm-impermanence 'sudo reboot' && echo "rebooting!" && sleep 30
else
  echo sleeping:
  sleep 2
fi
