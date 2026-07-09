# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "git";
  url = "ssh://git@github.com/esp0xdeadbeef/Webpage.git";
  ref = "refs/heads/main";
  rev = "22919a30fa37708b2410ee7cc292b54285287aa0";
  narHash = "sha256-RW4V1mU8JB0/1plcsEQJsXhTVYbz9kCEdotfxhQFqAE=";
}
