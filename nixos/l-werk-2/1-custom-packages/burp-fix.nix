{ config, pkgs, ... }:
{

  # creating a a softlink for burp shit (suite)
  environment.etc."burp/jython.jar" = {
    # If you have a jython package in your Nixpkgs, you can use it like:
    source = "${pkgs.jython}/jython.jar";
    # Alternatively, if you want to hardcode the current store path, you can:
    # source = "/nix/store/akb86svs9qd561a5l27252pqyd8dyds4-jython-2.7.4/jython.jar";
  };

  environment.etc."burp/jruby.jar" = {
    source = "${pkgs.jruby}/lib/jruby.jar";
  };
}
