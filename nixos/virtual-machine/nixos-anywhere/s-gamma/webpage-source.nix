# Host-local private source pin. Keep this out of the root flake inputs so
# unrelated hosts do not need access to this private repository.
builtins.fetchTree {
  type = "git";
  url = "ssh://git@github.com/esp0xdeadbeef/Webpage.git";
  ref = "refs/heads/main";
  rev = "325e8d3907592709dd4c8776973dc114f1c63364";
  narHash = "sha256-UWOzsKujRwKG5Xv39Ebq3yS1wYhrTYwFj7n+51Q8Pjk=";
}
