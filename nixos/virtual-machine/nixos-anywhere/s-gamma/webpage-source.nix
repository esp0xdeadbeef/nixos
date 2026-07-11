# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "github";
  owner = "esp0xdeadbeef";
  repo = "www";
  rev = "2193a552d0c1f7250087fda31392af75ab1dec44";
  narHash = "sha256-5qjDAneCzPL7WtbFOU6BN+rPlQLhoY6Zjy/5xy2vAHE=";
}
