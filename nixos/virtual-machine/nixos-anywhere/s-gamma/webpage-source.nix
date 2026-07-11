# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "github";
  owner = "esp0xdeadbeef";
  repo = "www";
  rev = "68b9099872e2af7fed2362edc93d66f370e413ee";
  narHash = "sha256-P3paC5BmP72qds+2hJlIcZaIpnizt+PkTtsVUXRFmfM=";
}
