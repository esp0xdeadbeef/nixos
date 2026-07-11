# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "git";
  url = "ssh://git@github.com/esp0xdeadbeef/Webpage.git";
  ref = "refs/heads/main";
  rev = "5f936e359336001e260604173a3f686c88c1d07c";
  narHash = "sha256-OjazAOXmLN7Eifd77HMrRQHzALawJxFN7TLVejEs0kE=";
}
