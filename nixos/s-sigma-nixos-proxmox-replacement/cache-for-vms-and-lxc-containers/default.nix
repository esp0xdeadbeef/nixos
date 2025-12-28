
# IDEA:
# nix-serve --listen /tmp/nix-serve

# from VM or lxc (bindfs), but ports are not open.. sad:
# nix store info --store http://localhost:5000

# so client needs:
# socat TCP-LISTEN:5000,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/tmp/nix-serve

#<interface type='socket'>
#  <source path='/tmp/nixnet.sock'/>
#  <model type='virtio'/>
#</interface>

{
  config,
  pkgs,
  lib,
  sops,
  ...
}:

{
  nix.settings = {
    # Enable binary cache signing
    secret-key-files = [ "/etc/nix/cache-priv-key.pem" ];

    # Serve binaries
    substituters = [ "http://127.0.0.1:5000" ];
  };


  services.nix-serve = {
    enable = true;
    secretKeyFile = "/etc/nix/cache-priv-key.pem";
    
  };




  # DON'T EVER USE THIS ON A PUBLIC EXPOSED SERVICE WITH THE KEYS USED IN YOUR CLIENT
  # The reason i do this, is that the services inside VM's are pwned anyways if the host is owned.
  systemd.services.make-key = {
wantedBy = ["multi-user.target"];
serviceConfig = {
ExecStart = ''
${nix}/bin/nix-store --generate-binary-cache-key \
  local-cache \
  /etc/nix/cache-priv-key.pem \
  /etc/nix/cache-pub.key

''
};
};

}
