{ pkgs
, lib ? pkgs.lib
, system ? pkgs.system
}:

let
  isLinux = builtins.match ".*-linux" system != null;
  isI686 = system == "i686-linux";
  isX86_64Linux = system == "x86_64-linux";
in
{
  autorecon = pkgs.callPackage ./autorecon { };
  mxbuild = pkgs.callPackage ./mxbuild { };
  pentest-workspace = pkgs.callPackage ./pentest-workspace { };
}
// lib.optionalAttrs (isLinux && !isI686) {
  android-emulator-sdk = pkgs.callPackage ./android-emulator-sdk { };
}
// lib.optionalAttrs isX86_64Linux {
  dell-openmanage = pkgs.callPackage ./dell-openmanage { };
  dell-suu = pkgs.callPackage ./dell-suu { };
  dell-system-update = pkgs.callPackage ./dell-system-update { };
}
  // lib.optionalAttrs (!isI686) {
  pentest-powershell = pkgs.callPackage ./pentest-powershell { };
}
