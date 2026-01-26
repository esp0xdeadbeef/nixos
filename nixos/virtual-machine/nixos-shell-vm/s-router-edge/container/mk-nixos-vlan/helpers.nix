{ lib }:
{
  stripCidr = s: lib.head (lib.splitString "/" s);

  ipv4Base3 = ip4:
    let oct = lib.splitString "." (lib.head (lib.splitString "/" ip4));
    in lib.concatStringsSep "." (lib.take 3 oct);

  defaultPool4 = ip4:
    let b = (lib.take 3 (lib.splitString "." (lib.head (lib.splitString "/" ip4))));
    in "${lib.concatStringsSep "." b}.100 - ${lib.concatStringsSep "." b}.200";
}

