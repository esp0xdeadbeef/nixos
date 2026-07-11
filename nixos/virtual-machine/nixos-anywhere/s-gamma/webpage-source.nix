# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "git";
  url = "ssh://git@github.com/esp0xdeadbeef/Webpage.git";
  ref = "refs/heads/main";
  rev = "6bec1fd9c5413649c205bab1534b15d55f1dfe44";
  narHash = "sha256-DJo16Mxq5AaVx2pwaib2ePVa9UrmoxukZlA69KP4fqE=";
}
