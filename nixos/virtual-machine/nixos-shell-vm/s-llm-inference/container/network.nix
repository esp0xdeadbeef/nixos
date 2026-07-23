{ ... }:

{
  # Follow the s-test container convention: NetworkManager configures the
  # veth supplied by extraVeths, and the container does not inherit host DNS.
  networking.networkmanager.enable = true;
  services.resolved.enable = false;
}
