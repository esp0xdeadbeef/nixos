#!/usr/bin/env bash
# output results should be the following:
# Up and downstream vlan interfaces, ips(ipv4 and ipv6 of specific nodes), routes (ipv4 and ipv6)
nix eval --file lib/debug/debug-eval.nix --json | jq
