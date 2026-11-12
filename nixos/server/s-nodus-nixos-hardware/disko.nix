# Board-independent microSD layout: the canonical s-nodus disko configuration.
#
# This copy only differs from s-nodus in its board support (kernel/DTB/FIT via
# inputs.nixos-hardware), so the disk layout is imported rather than duplicated.
{ ... }@args:
import ../s-nodus/disko.nix args
