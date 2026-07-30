{ relativeRepo }: final: prev:
import (relativeRepo.module "pkgs") {
  pkgs = final;
  inherit (prev) lib;
  system = prev.stdenv.hostPlatform.system;
}
