# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "git";
  url = "ssh://git@github.com/esp0xdeadbeef/Webpage.git";
  ref = "refs/heads/main";
  rev = "6b8ebdb6a9d0a3fe102683adebc9745106b41c59";
  narHash = "sha256-yZD8+jwpm1DtFbr4euw0C+D3Rqlyv4a/a9Ind41Skko=";
}
