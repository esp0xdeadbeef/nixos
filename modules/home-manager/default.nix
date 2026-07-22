{ relativeRepo, ... }:

{
  desktopI3 = import (relativeRepo.module "profiles/home-manager/desktop-i3");
}
