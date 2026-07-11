# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "github";
  owner = "esp0xdeadbeef";
  repo = "www";
  rev = "19d7551b8243847977c056fa6ba9c081745ba4da";
  narHash = "sha256-E+VuNHbaaHnnuZb/bX8GFPL+e5yXyoHzChHzIiO++8g=";
}
